//
//  RedditLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa
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
            return completion([LoadableImageEntity.image(url, cacheFileUrl, attributes)])
        case .failed:
            return completion([LoadableImageEntity.image(url, cacheFileUrl, attributes)])
        default:
            break
        }
    })

}

fileprivate func entities(from json: Data, url: URL) -> [LoadableImageEntity] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
        let doc = try decoder.decode(RedditLoader.SubredditPage.self, from: json)
        var results = doc.data.children.compactMap({ (child) -> (String, RedditLoader.SubredditPage.Child.ChildData)? in
            let d = child.data
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
            return child.data.preview?.images?.first?.source?.url.map {($0, d)}
        }).map {
            ($0.0.replacingOccurrences(of: "&amp;", with: "&"), $0.1)
            } .compactMap{ (u, d) -> (URL, RedditLoader.SubredditPage.Child.ChildData)? in
                URL(string: u).map { ($0, d) }
            } .map {
                LoadableImageEntity.placeHolder($0.0,
                                                false,
                                                ["title": $0.1.title ?? "",
                                                 "author": $0.1.author ?? "",
                                                 "text": $0.1.selftext ?? "",
                                                 "domain": $0.1.domain ?? ""])
                
        }
        
        if let after = doc.data.after {
            let path = url.path
            let schema = url.scheme!
            let host = url.host!
            
            let nextUrl = URL(string: "\(schema)://\(host)\(path)?count=25&after=\(after)")!
            results.append(LoadableImageEntity.batchPlaceHolder(nextUrl, false))
        }
        return results
        
    } catch let err {
        print(err)
    }
    return []
}



final class RedditLoader: AbstractImageLoader {
    class DBWrapper {
        typealias DBHandle = OpaquePointer?
        typealias Statement = OpaquePointer?

        var dbHandle: DBHandle
        var q : DispatchQueue = DispatchQueue(label: "dbq")
        
        var queryStmt1 : Statement
        var queryStmt2 : Statement
        var saveStmt: Statement

        init(external: Bool) throws {
            //self.subreddit = subreddit
            let path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first!.appending("/reddit/")
            let dbFilename = (external ? path + ".external/" : path) + "/cache.db"
            try dbFilename.withCString { (pFilename) in
                guard sqlite3_open(pFilename, &dbHandle) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed opening cache.db"])
                }
            }
            
            let initSql = "CREATE TABLE IF NOT EXISTS rdt_child_data (url text, hash text, sub text, post_id text);"
            try initSql.withCString { (initCStr) in
                var statement : Statement
                guard sqlite3_prepare_v2(dbHandle, initCStr, Int32(initSql.lengthOfBytes(using: .utf8)), &statement, nil) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed prepare initSql"])
                }
                guard sqlite3_step(statement) == SQLITE_DONE && sqlite3_finalize(statement) == SQLITE_OK else {
                    throw NSError(domain: "DBWrapper", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Failed exec initSql"])
                }
            }
            
            let indexSql = "CREATE INDEX IF NOT EXISTS rdt_sub_post ON rdt_child_data (sub, post_id);"
            try indexSql.withCString { (initCStr) in
                var statement : Statement
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
            
            let save = "INSERT INTO rdt_child_data (sub, url, post_id, hash) VALUES (?, ?, ?, ?);"
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
        try! self.sqlite = DBWrapper(external: external)
        self.cacheFunc = { (url: URL) -> URL?  in
            let downloadPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first!
            let fileName = url.lastPathComponent
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") || fileName.hasSuffix(".gif") {
                if external {
                    let cachePath = downloadPath + "/reddit/.external/" + name + "/" + fileName
                    return URL(fileURLWithPath: cachePath)
                }
                let cachePath = downloadPath + "/reddit/" + name + "/" + fileName
                return URL(fileURLWithPath: cachePath)
            }
            
            if url.host?.contains("v.redd.it") ?? false {
                if external {
                    let cachePath = downloadPath + "/reddit/.external/" + name + "/" + url.pathComponents.joined(separator: "_") + ".mp4"
                    return URL(fileURLWithPath: cachePath)
                }

                let cachePath = downloadPath + "/reddit/" + name + url.pathComponents.joined(separator: "_") + ".mp4"
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
        let task = session.dataTask(with: url) { data, response, err in
            if let data = data {
                return completion(entities(from: data, url: url))
            }
            return completion([])
        }
        task.resume()
    }
    
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, attributes: [String: Any], completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        // Note: Such configuration requires that .redd.it domains added to /etc/hosts
        let useRedditSession = url.host!.hasSuffix(".redd.it") ||
            url.host!.hasSuffix(".redditmedia.com")
        let s = useRedditSession ? redditSession : session
        //let fileName = url.lastPathComponent
        let task = s.downloadTask(with: url) { (fileUrl, response, err) in
            if let err = err {
                print("error loading \(url.absoluteString): \(err.localizedDescription)")
            }
            if let fileUrl = fileUrl, let cacheFileUrl = cacheFileUrl {
                let contentType = (response as! HTTPURLResponse).allHeaderFields["Content-Type"] as? String
                print("did fetch: \(url); " + (contentType.map { "type: " + $0 } ?? ""))
                switch contentType {
                case "image/jpeg", "image/png", "image/gif":
                    if let _ = NSImage(contentsOf: fileUrl) {
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        }
                        return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                    }
                case "video/mp4":
                    
                    if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        
                        try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        generateThumbnail(for: url, cacheFileUrl: cacheFileUrl, attributes: attributes, completion: completion)
                        /*
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
                                return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                            case .failed:
                                return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                            default:
                                break
                            }
                        })
                         */
                        
                    } else {
                        return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                    }
                default:
                    break
                }
                /*
                if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".gif"),
                    let _ = NSImage(contentsOf: fileUrl) {
                    if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                    }
                    return completion([EntityKind.image(url, cacheFileUrl)])
                }
                if contentType?.contains("video/mp4") ?? false {
                    if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                    }
                    return completion([EntityKind.image(url, cacheFileUrl)])
                }
                */
                //return completion([EntityKind.image(image)])
            }
            return completion([])
        }
        task.resume()
    }
    
    override func loadCachedPlaceHolder(with url: URL, attributes: [String: Any]) -> EntityKind? {
        let cacheFileUrl = cacheFunc(url)
        if let cacheFileUrl = cacheFileUrl {
            if cacheFileUrl.pathExtension == "mp4" {
                if fileManager.fileExists(atPath: cacheFileUrl.path) {
                    return EntityKind.image(url, cacheFileUrl, attributes)
                }
            }
            if fileManager.fileExists(atPath: cacheFileUrl.path), let _ = NSImage(contentsOf: cacheFileUrl) {
                return EntityKind.image(url, cacheFileUrl, attributes)
            }
        }
        return nil
    }
    
    override func cacheFileUrl(for url: URL) -> URL? {
        return self.cacheFunc(url)
    }
    
    override func loadFirstPage(completion: @escaping ([EntityKind]) -> ()) {
        let firstPageUrl = URL(string: "https://www.reddit.com/r/\(name)/.json")!
        let task = session.dataTask(with: firstPageUrl) {
            (data, response, error) in
            if let data = data {
                completion(entities(from: data, url: firstPageUrl))
            }
        }
        task.resume()
    }
}
