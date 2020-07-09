//
//  RedditLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

#if os(macOS)
import Cocoa
#elseif os(iOS)
import UIKit
import MobileCoreServices
#endif
import AVFoundation
import SQLite3

func generateThumbnail(for url: URL, cacheFileUrl: URL, attributes:[String: Any] , completion: @escaping ([LoadableImageEntity])->()) {
    let asset = AVAsset(url: cacheFileUrl)
    asset.loadValuesAsynchronously(forKeys: ["playable"], completionHandler: {
        switch asset.statusOfValue(forKey: "playable", error: nil) {
        case .loaded:
            let igen = AVAssetImageGenerator(asset: asset)
            let time = CMTime(seconds: asset.duration.seconds * 0.33, preferredTimescale: asset.duration.timescale)
            let videoThumb = URL(fileURLWithPath: cacheFileUrl.path).appendingPathExtension("vthumb")
            
            if let image = try? igen.copyCGImage(at: time, actualTime: nil),
                let dest = CGImageDestinationCreateWithURL(videoThumb as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
            return completion([LoadableImageEntity.image((url, cacheFileUrl, attributes))])
        case .failed:
            return completion([LoadableImageEntity.image((url, cacheFileUrl, attributes))])
        default:
            break
        }
    })

}
fileprivate func previewSize(for child: RedditLoader.SubredditPage.Child.ChildData) -> CGSize? {
    if let source = child.preview?.images?.first?.source {
        return CGSize(width: source.width, height: source.height)
    }
    return nil
}
typealias ChildData = RedditLoader.SubredditPage.Child.ChildData
fileprivate func entities(from json: Data, url: URL) -> [LoadableImageEntity] {
    let (c, after) = children(from: json)
    return entities(from: c, url: url, after: after)
}

fileprivate func entities(from children: [ChildData], url pageUrl: URL?, after: String?) -> [LoadableImageEntity] {
    var results = children.compactMap({ (child) -> (String, ChildData)? in
        let d = child
        if d.isSelf ?? false {
            return nil
        }
        if d.isRedditMediaDomain ?? false, let url = d.url, let domain = d.domain, domain.hasSuffix(".redd.it") || domain.hasSuffix(".redditmedia.com") {
            if domain.hasSuffix("v.redd.it"), let videoPreview = d.media?.redditVideo {
                if let url = videoPreview.fallbackUrl ?? videoPreview.scrubberMediaUrl {
                    return (url, d)
                }
            }
            return (url, d)
        }
        if let media = d.media, let tn = media.oembed?.thumbnailUrl {
            if tn.hasPrefix("https://i.imgur.com/"), tn.hasSuffix(".jpg?fbplay") {
                let url = tn.replacingOccurrences(of: ".jpg?fbplay", with: ".mp4")
                return (url, d)
            }
        }
        if let videoPreview = d.preview?.redditVideoPreview {
            if let url = videoPreview.fallbackUrl ?? videoPreview.scrubberMediaUrl {
                return (url, d)
            }
        }
        if let resolutions = d.preview?.images?.first?.resolutions {
            return resolutions.max(by: { $0.width * $0.height < $1.width * $1.height })?.url.map { ($0, d) }
        }
        return child.preview?.images?.first?.source?.url.map {($0, d)}
    }).map {
        ($0.0.replacingOccurrences(of: "&amp;", with: "&"), $0.1)
        } .compactMap{ (u, d) -> (URL, ChildData)? in
            URL(string: u).map { ($0, d) }
        } .map { (u: URL, d: ChildData) -> LoadableImageEntity in
            let attr : [String: Any] = previewSize(for: d).map { (size: CGSize) -> [String: Any] in
                ["title": d.title ?? "",
                 "author": d.author ?? "",
                 "text": d.selftext ?? "",
                 "domain": d.domain ?? "",
                 "size": size]
                } ??
                ["title": d.title ?? "",
                 "author": d.author ?? "",
                 "text": d.selftext ?? "",
                 "domain": d.domain ?? ""]
            return LoadableImageEntity.placeHolder((u,
                                                    false,
                                                    attr))
            
    }
    
    if let after = after, let pageUrl = pageUrl {
        let path = pageUrl.path
        let schema = pageUrl.scheme!
        let host = pageUrl.host!
        
        let nextUrl = URL(string: "\(schema)://\(host)\(path)?count=25&after=\(after)")!
        results.append(LoadableImageEntity.batchPlaceHolder((nextUrl, false)))
    }
    return results
}

fileprivate func children(from json: Data) -> ([ChildData], String?) {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
        let doc = try decoder.decode(RedditLoader.SubredditPage.self, from: json)
        return (doc.data.children.map { $0.data }, doc.data.after)
        
    } catch let err {
        print(err)
    }
    return ([], nil)
}



class RedditLoader: AbstractImageLoader {
    class DBWrapper {
        typealias DBHandle = OpaquePointer?
        typealias Statement = OpaquePointer?

        var dbHandle: DBHandle = DBHandle(nilLiteral: ())
        var q : DispatchQueue = DispatchQueue(label: "dbq")
        
        var queryStmt1 = Statement(nilLiteral: ())
        var queryStmt2 = Statement(nilLiteral: ())
        var saveStmt = Statement(nilLiteral: ())

        init(external: Bool) throws {
            //self.subreddit = subreddit
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/reddit/")
            let dbFilename = (external ? path + ".external/" : path) + "/cache.db"
            try dbFilename.withCString { (pFilename) in
                guard sqlite3_open(pFilename, &dbHandle) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed opening cache.db"])
                }
            }
            
            let initSql = "CREATE TABLE IF NOT EXISTS rdt_child_data (url text, hash text, sub text, post_id text UNIQUE);"
            
            try initSql.withCString { (initCStr) in
                var statement = Statement(nilLiteral: ())
                guard sqlite3_prepare_v2(dbHandle, initCStr, Int32(initSql.lengthOfBytes(using: .utf8)), &statement, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare initSql"])
                }
                guard sqlite3_step(statement) == SQLITE_DONE && sqlite3_finalize(statement) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed exec initSql"])
                }
            }
            
            let indexSql = "CREATE INDEX IF NOT EXISTS rdt_sub_post ON rdt_child_data (sub, post_id);"
            try indexSql.withCString { (initCStr) in
                var statement = Statement(nilLiteral: ())
                guard sqlite3_prepare_v2(dbHandle, initCStr, Int32(indexSql.lengthOfBytes(using: .utf8)), &statement, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare indexSql"])
                }
                guard sqlite3_step(statement) == SQLITE_DONE && sqlite3_finalize(statement) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed exec indexSql"])
                }
            }
            
            let query1 = "SELECT hash FROM rdt_child_data WHERE post_id = ? AND sub = ?;"
            try query1.withCString({ (cstr) in
                guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query1.lengthOfBytes(using: .utf8)), &self.queryStmt1, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare query1"])
                }
            })
            let query2 = "SELECT hash FROM rdt_child_data WHERE url = ?;"
            try query2.withCString({ (cstr) in
                guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query2.lengthOfBytes(using: .utf8)), &self.queryStmt2, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare query2"])
                }
            })
            
            let save = "INSERT OR REPLACE INTO rdt_child_data (sub, url, post_id, hash) VALUES (?, ?, ?, ?);"
            try save.withCString({ (cstr) in
                guard sqlite3_prepare_v2(dbHandle, cstr, Int32(save.lengthOfBytes(using: .utf8)), &self.saveStmt, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare savestmt"])
                }
            })
        }
        func query(sub: String, post: String, completion: @escaping (String?) -> () ) {
            q.async {
                let result = post.withCString { (postStr) -> String? in
                    sub.withCString { (subStr) -> String? in
                        guard sqlite3_bind_text(self.queryStmt1, 1, subStr, Int32(sub.utf8.count), nil) == SQLITE_OK
                            && sqlite3_bind_text(self.queryStmt1, 2, postStr, Int32(post.utf8.count), nil) == SQLITE_OK else {
                                return nil
                        }
                        switch sqlite3_step(self.queryStmt1) {
                        case SQLITE_ROW:
                            return String(cString: sqlite3_column_text(self.queryStmt1, 0))
                        default:
                            break
                        }
                        return nil
                    }
                }
                sqlite3_reset(self.queryStmt1)
                completion(result)
            }
        }
        func query(url: String, completion: @escaping (String?) -> () ) {
            q.async {
                let result = url.withCString { (urlStr) -> String? in
                    guard sqlite3_bind_text(self.queryStmt2, 1, urlStr, Int32(url.utf8.count), nil) == SQLITE_OK else {
                        return nil
                    }
                    switch sqlite3_step(self.queryStmt2) {
                    case SQLITE_ROW:
                        return String(cString: sqlite3_column_text(self.queryStmt2, 0))
                    default:
                        break
                    }
                    return nil
                }
                sqlite3_reset(self.queryStmt2)
                completion(result)
            }
        }
        
        func queryBatch(sub: String, after: String = "", count: Int) -> [(String, String)] /*[(post_id, hash)]*/ {
            var result :[(String, String)] = []
            let query1 = "SELECT post_id, MIN(hash) FROM rdt_child_data WHERE sub = ?1 AND post_id > ?2 GROUP BY post_id ORDER BY post_id LIMIT ?3;"
            q.sync {
                try? query1.withCString({ (cstr) in
                
                    var stmt = Statement(nilLiteral: ())
                    guard sqlite3_prepare_v2(dbHandle, cstr, Int32(query1.lengthOfBytes(using: .utf8)), &stmt, nil) == SQLITE_OK else {
                        throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed preparing query1"])
                    }
                    
                    guard after.withCString({ (afterStr) -> Bool in
                        guard sub.withCString({(subStr) -> Bool in
                            let r1 = sqlite3_bind_text(stmt, 1, subStr, Int32(strlen(subStr)), nil)
                            let r2 = sqlite3_bind_text(stmt, 2, afterStr, Int32(strlen(afterStr)), nil)
                            let r3 = sqlite3_bind_int(stmt, 3, Int32(count))
                            guard  (r1 == SQLITE_OK) && (r2 == SQLITE_OK) && (r3 == SQLITE_OK) else {
                                return false
                            }
                            var r : Int32
                            r = sqlite3_step(stmt)
                            while (r == SQLITE_ROW) {
                                if let pIdStr = sqlite3_column_text(stmt, 0),
                                    let hashStr = sqlite3_column_text(stmt, 1) {
                                    let pId = String(cString: pIdStr)
                                    let hash = String(cString: hashStr)
                                    result.append((pId, hash))
                                }
                                r = sqlite3_step(stmt)
                            }
                            
                            return true
                        }) else {return false}
                        return true
                    }) else {
                        throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed binding query1"])
                    }
                    _ = sqlite3_finalize(stmt)
                })
            }
            return result
        }
        func save(sub: String, url: String, postId: String, hash: String) {
            q.async {
                
                url.withCString { (urlStr) in
                    postId.withCString { (postStr) in
                        sub.withCString { (subStr) in
                            hash.withCString { (hashStr) in
                                guard sqlite3_bind_text(self.saveStmt, 1, subStr, Int32(sub.utf8.count), nil) == SQLITE_OK else {
                                    return
                                }
                                guard sqlite3_bind_text(self.saveStmt, 2, urlStr, Int32(url.utf8.count), nil) == SQLITE_OK else {
                                    return
                                }
                                guard sqlite3_bind_text(self.saveStmt, 3, postStr, Int32(postId.utf8.count), nil) == SQLITE_OK else {
                                    return
                                }
                                guard sqlite3_bind_text(self.saveStmt, 4, hashStr, Int32(hash.utf8.count), nil) == SQLITE_OK else {
                                    return
                                }
//                                guard sqlite3_bind_text(self.saveStmt, 5, postStr, Int32(postId.utf8.count), nil) == SQLITE_OK else {
//                                    return
//                                }
                                sqlite3_step(self.saveStmt)
                            }
                        }
                    }
                }
                sqlite3_reset(self.saveStmt)
            }
        }
        deinit {
            q.sync {
                sqlite3_finalize(queryStmt1)
                sqlite3_finalize(queryStmt2)
                sqlite3_close(dbHandle)
            }
        }
    }
    static var sharedExternalDB: DBWrapper!
    static var sharedInternalDB: DBWrapper!
    
    typealias EntityKind = LoadableImageEntity

    let name: String
    let session: URLSession
    let redditSession: URLSession
    let fileManager = FileManager()
    var cacheFunc: ((URL) -> URL?)

    let sqlite : DBWrapper
    init(name: String, session: URLSession, external: Bool = false) {
        self.name = name
        self.session = session
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.redditSession = URLSession(configuration: configuration)
        if external {
            if RedditLoader.sharedExternalDB == nil {
                RedditLoader.sharedExternalDB = try! DBWrapper(external: true)
            }
            self.sqlite = RedditLoader.sharedExternalDB
        } else {
            if RedditLoader.sharedInternalDB == nil {
                RedditLoader.sharedInternalDB = try! DBWrapper(external: false)
            }
            self.sqlite = RedditLoader.sharedInternalDB
        }
        self.cacheFunc = { (url: URL) -> URL?  in
            let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            let fileName = url.lastPathComponent
            
            if url.host?.contains("v.redd.it") ?? false {
                if external {
                    let cachePath = downloadPath + "/reddit/.external/" + name + "/" + url.pathComponents.joined(separator: "_") + ".mp4"
                    return URL(fileURLWithPath: cachePath)
                }

                let cachePath = downloadPath + "/reddit/" + name + url.pathComponents.joined(separator: "_") + ".mp4"
                return URL(fileURLWithPath: cachePath)
            }
            
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") || fileName.hasSuffix(".gif") {
                if external {
                    let cachePath = downloadPath + "/reddit/.external/" + name + "/" + fileName
                    return URL(fileURLWithPath: cachePath)
                }
                let cachePath = downloadPath + "/reddit/" + name + "/" + fileName
                return URL(fileURLWithPath: cachePath)
            }
            
            
            return nil
        }
    }
    struct SubredditPage : Codable {
        let kind: String
        struct Media: Codable {
            struct Embed: Codable {
                let providerUrl: String?
                let description: String?
                let title: String?
                let thumbnailUrl: String?
                let html: String?
                let type: String?
            }
            
            let type: String?
            let oembed: Embed?
            let redditVideo: VideoPreview?
        }
        struct VideoPreview: Codable {
            let fallbackUrl: String?
            let scrubberMediaUrl: String?
            let hlsUrl: String?
            let duration: Int?
        }
        struct Preview: Codable {
            struct Image: Codable {
                struct Source: Codable {
                    let url: String?
                    let width: Int
                    let height: Int
                }
                let source: Source?
                let resolutions: [Source]?
                
            }
            let images: [Preview.Image]?
            let redditVideoPreview: VideoPreview?
        }
        struct Child: Codable {
            let kind: String
            struct ChildData: Codable {
                
                let author: String?
                let title: String?
                let selftext: String?
                let preview: Preview?
                let url: String?
                let permalink: String?
                let domain: String?
                let isRedditMediaDomain: Bool?
                let isSelf: Bool?
                let media: Media?
                let id: String?
                let createdUtc: Int?
            }
            let data: ChildData
        }
        struct DataObj: Codable {
            let children: [Child]
            let after: String?
            let before: String?
        }
        let data: DataObj
        let url: String?
    }
    override func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) -> ()) {
        let downPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/\(name)/.json"
        let saveCache = fileManager.fileExists(atPath: downPath)

        let task = session.dataTask(with: url) { [weak self] data, response, err in
            guard let self = self else { return }
            if let data = data {
                //return completion(entities(from: data, url: url))

                let (ch, aft) = children(from: data)
                if saveCache {
                    let hash = UUID().uuidString
                    let path = downPath + "/" + hash + ".json"
                    do {
                        try data.write(to: URL(fileURLWithPath: path))
                        _ = ch.map { (d) in
                            if let link = d.permalink, let id = d.id {
                                self.sqlite.save(sub: self.name, url: link, postId: id, hash: hash)
                            }
                        }
                    } catch {
                        
                    }
                }
                
                return completion(entities(from: ch, url: url, after: aft))
            }
            return completion([])
        }
        task.resume()
    }
    
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, attributes: [String: Any], completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        // Note: Such configuration requires that .redd.it domains added to /etc/hosts
        let useRedditSession = false // url.host!.hasSuffix(".redd.it") ||
//            url.host!.hasSuffix(".redditmedia.com")
        let s = useRedditSession ? redditSession : session
        //let fileName = url.lastPathComponent
        let task = s.downloadTask(with: url) { [weak self] (fileUrl, response, err)  in
            guard let self = self else {return}
            if let err = err {
                print("error loading \(url.absoluteString): \(err.localizedDescription)")
            }
            if let fileUrl = fileUrl, let cacheFileUrl = cacheFileUrl {
                let contentType = (response as! HTTPURLResponse).allHeaderFields["Content-Type"] as? String
                print("did fetch: \(url); " + (contentType.map { "type: " + $0 } ?? ""))
                
                return autoreleasepool(invoking: { ()->() in
                    switch contentType {
                        #if os(macOS)
                        /*
                    case "image/jpeg", "image/png":
                        if let provider = fileUrl.path.withCString({ CGDataProvider(filename: $0)}) {
                            let img: CGImage?
                            if contentType == "image/jpeg" {
                                img = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                            } else {
                                img = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                            }
                            
                            if let img = img {
                                let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                                if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                                    try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                                }
                                var extendedAttr = attributes
                                extendedAttr["thumbnail"] = nsImg
                                //extendedAttr["size"] = NSSize(width: img.width, height: img.height)
                                return completion([EntityKind.image(url, cacheFileUrl, extendedAttr)])
                            }
                        }
                        return completion([])
                        */
                    case  "image/jpeg", "image/png", "image/gif":
                        if let d = try? Data(contentsOf: fileUrl) {
                            if let img = NSBitmapImageRep(data: d)?.cgImage {
                                let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                                if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                                    try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                                }
                                var extendedAttr = attributes
                                extendedAttr["thumbnail"] = nsImg
                                return completion([EntityKind.image((url, cacheFileUrl, extendedAttr))])

                            }
                        }
                        return completion([])
                        #elseif os(iOS)
                    case "image/jpeg", "image/png", "image/gif":
                        if let img = UIImage(contentsOfFile: fileUrl.path) {
                            if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                                try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                            }
                            var attributes = attributes
                            attributes["size"] = img.size
                            return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                        }
                        return completion([])
                        #endif
                    case "video/mp4":
                        
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                            generateThumbnail(for: url, cacheFileUrl: cacheFileUrl, attributes: attributes, completion: completion)
                        } else {
                            return completion([EntityKind.image((url, cacheFileUrl, attributes))])
                        }
                    default:
                        return completion([])
                    }
                })
            }
            return completion([])
        }
        task.resume()
    }
    
    override func loadCachedPlaceHolder(with url: URL, attributes: [String: Any]) -> EntityKind? {
        return autoreleasepool { () -> EntityKind? in
            let cacheFileUrl = cacheFunc(url)
            if let cacheFileUrl = cacheFileUrl {
                if cacheFileUrl.pathExtension == "mp4" {
                    if fileManager.fileExists(atPath: cacheFileUrl.path) {
                        return EntityKind.image((url, cacheFileUrl, attributes))
                    }
                }
                #if os(macOS)
                if fileManager.fileExists(atPath: cacheFileUrl.path){
                    if let provider = cacheFileUrl.path.withCString({CGDataProvider(filename: $0 )}) {
                        var img : NSImage?
                        switch url.pathExtension.lowercased() {
                        case "jpeg", "jpg":
                            if let i = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                                img = NSImage(cgImage: i, size: NSSize(width: i.width, height: i.height))
                            }
                            
                        case "png":
                            if let i = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                                img = NSImage(cgImage: i, size: NSSize(width: i.width, height: i.height))
                            }
                        case "gif":
                            img = NSImage(contentsOf: cacheFileUrl)
                        default:
                            break
                        }
                        if let img = img {
                            var extendedAttr = attributes
                            extendedAttr["thumbnail"] = img
                            return EntityKind.image((url, cacheFileUrl, extendedAttr))
                        }
                    }
                }
                #elseif os(iOS)
                if fileManager.fileExists(atPath: cacheFileUrl.path), let _ = UIImage(contentsOfFile: cacheFileUrl.path) {
                    return EntityKind.image(url, cacheFileUrl, attributes)
                }
                #endif
            }
            return nil
        }
    }
    
    override func cacheFileUrl(for url: URL) -> URL? {
        return self.cacheFunc(url)
    }
    
    override func loadFirstPage(completion: @escaping ([EntityKind]) -> ()) {
        let firstPageUrl = URL(string: "https://www.reddit.com/r/\(name)/.json")!
        let downPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/\(name)/.json"
        let saveCache = fileManager.fileExists(atPath: downPath)
        let task = session.dataTask(with: firstPageUrl) {
            [weak self] (data, response, error) in
            guard let self = self else { return }
            if let data = data {
                let (ch, aft) = children(from: data)
                
                if saveCache {
                    let hash = UUID().uuidString
                    let path = downPath + "/" + hash + ".json"
                    do {
                        try data.write(to: URL(fileURLWithPath: path))
                        _ = ch.map { (d) in
                            if let link = d.permalink, let id = d.id {
                                self.sqlite.save(sub: self.name, url: link, postId: id, hash: hash)
                            }
                        }
                    } catch {
                        
                    }
                }
               
                return completion(entities(from: ch, url: firstPageUrl, after: aft))
            }
            return completion([])
        }
        task.resume()
    }
    
    static var existingSubreddits = Set<String>()
    
    class func subRedditAutocompletion(for partial: String) -> [String] {
        if existingSubreddits.isEmpty {
            // Load again
            let fm = FileManager.default
            let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            _ = ["/reddit/.external", "/reddit"].filter {
                fm.fileExists(atPath: downloadPath + $0)
            } .map {
                let base = downloadPath + $0
                _ = try? fm.contentsOfDirectory(atPath: downloadPath + $0).filter({ (name) -> Bool in
                    var isDir = ObjCBool(false)
                    fm.fileExists(atPath: base + "/" + name, isDirectory: &isDir)
                    return isDir.boolValue && !name.hasPrefix(".")
                }).map {
                    _ = existingSubreddits.insert($0.lowercased())
                }
            }
        }
        let lowerCasedPartial = partial.lowercased()
        let candidates = existingSubreddits.filter { (candidate) -> Bool in
            candidate.hasPrefix(lowerCasedPartial)
        }
        return [String](candidates).sorted()
    }
}

final class OfflineRedditLoader: RedditLoader {
    override func loadFirstPage(completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        let downPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/\(name)/.json"
        DispatchQueue.global().async {
            var jsons = [String: [ChildData]]()
            let list = self.sqlite.queryBatch(sub: self.name, count: 10)
            var result: [RedditLoader.EntityKind] = list.compactMap { (pair) -> RedditLoader.EntityKind? in
                var d = jsons[pair.1]
                if d == nil {
                    do {
                        let cached = try Data(contentsOf: URL(fileURLWithPath: downPath + "/" + pair.1 + ".json"))
                        let (cachedChildren, _) = children(from: cached)
                        jsons[pair.1] = cachedChildren
                        d = cachedChildren
                    } catch {
                        return nil
                    }
                }
                return entities(from: d!.filter({ (cd) -> Bool in
                    cd.id == pair.0
                }), url: nil, after: nil).first
            }
            if let l = list.last, let placeHolderUrl = URL(string: "after://\(self.name)/\(l.0)") {
                result.append(RedditLoader.EntityKind.batchPlaceHolder((placeHolderUrl, false)))
            }
            completion(result)
        }
    }
    
    override func loadNextBatch(with url: URL, completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        guard let scheme = url.scheme, scheme == "after" else {
            return completion([])
        }
        let p = url.path
        let idx = p.index(after: p.startIndex)
        let after = p.suffix(from: idx)
        
        let downPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/\(name)/.json"
        DispatchQueue.global().async {
            var jsons = [String: [ChildData]]()
            let list = self.sqlite.queryBatch(sub: self.name, after: String(after), count: 10)
            var result: [RedditLoader.EntityKind] = list.compactMap { (pair) -> RedditLoader.EntityKind? in
                var d = jsons[pair.1]
                if d == nil {
                    do {
                        let cached = try Data(contentsOf: URL(fileURLWithPath: downPath + "/" + pair.1 + ".json"))
                        let (cachedChildren, _) = children(from: cached)
                        jsons[pair.1] = cachedChildren
                        d = cachedChildren
                    } catch {
                        return nil
                    }
                }
                return entities(from: d!.filter({ (cd) -> Bool in
                    cd.id == pair.0
                }), url: nil, after: nil).first
            }
            if let l = list.last, let placeHolderUrl = URL(string: "after://\(self.name)/\(l.0)") {
                result.append(RedditLoader.EntityKind.batchPlaceHolder((placeHolderUrl, false)))
            }
            completion(result)
        }
    }
    /*
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, attributes: [String : Any], completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        DispatchQueue.global().async {
            if let cacheFileUrl = cacheFileUrl {
                switch cacheFileUrl.pathExtension.lowercased() {
                case "jpeg", "png", "gif", "jpg":
                    #if os(macOS)
                    
                    if self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                    }
                    
                    #elseif os(iOS)
                    
                    if self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        var attributes = attributes
                        if let img = UIImage(contentsOfFile: cacheFileUrl.path) {
                            attributes["size"] = img.size
                            return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                        }
                    }
                    
                    #endif
                case "mp4":
                    if self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                    }
                default:
                    break
                }
            }
            return completion([])
        }
    }
 */
}
