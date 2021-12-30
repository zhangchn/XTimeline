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
typealias ChildData = SubredditPage.Child.ChildData
fileprivate func previewSize(for child: ChildData) -> CGSize? {
    if let source = child.preview?.images?.first?.source {
        return CGSize(width: source.width, height: source.height)
    }
    return nil
}

fileprivate func entities(from json: Data, url: URL) -> [LoadableImageEntity] {
    let (c, after) = children(from: json)
    return entities(from: c, url: url, after: after)
}

fileprivate func entities(from children: [ChildData], url pageUrl: URL?, after: String?) -> [LoadableImageEntity] {
    var results = children.flatMap({ (child) -> [(String, ChildData)] in
        let d = child
        if d.isSelf ?? false {
            return []
        }
        if d.isRedditMediaDomain ?? false, let url = d.url, let domain = d.domain, domain.hasSuffix(".redd.it") || domain.hasSuffix(".redditmedia.com") {
            if domain.hasSuffix("v.redd.it"), let videoPreview = d.media?.redditVideo {
                if let url = videoPreview.fallbackUrl ?? videoPreview.scrubberMediaUrl {
                    return [(url, d)]
                }
            }
            return [(url, d)]
        }
        if let media = d.media, let tn = media.oembed?.thumbnailUrl {
            if tn.hasPrefix("https://i.imgur.com/"), tn.hasSuffix(".jpg?fbplay") {
                let url = tn.replacingOccurrences(of: ".jpg?fbplay", with: ".mp4")
                return [(url, d)]
            }
        }
        if let mediaMetadata = d.mediaMetadata {
            return mediaMetadata.compactMap { (key, metadataItem) -> (String, ChildData)? in
                if let m = metadataItem.m, let s = metadataItem.s {
                    switch m.lowercased() {
                    case "image/mp4", "image/gif":
                        if let u1 = s.mp4 {
                            return (u1, d)
                        } else if let u2 = s.gif {
                            return (u2, d)
                        }
                    case "image/jpeg", "image/jpg", "image/png":
                        if let u3 = s.u {
                            return (u3, d)
                        }
                    default:
                        print("metadata mime!!!: \(m)")
                    }
                } else {
                    print("no metadata mime or source: \(metadataItem)")
                }
                return nil
            }
        }
        if let videoPreview = d.preview?.redditVideoPreview {
            if let url = videoPreview.fallbackUrl ?? videoPreview.scrubberMediaUrl {
                return [(url, d)]
            }
        }
        if let resolutions = d.preview?.images?.first?.resolutions {
            if let result = resolutions.max(by: { $0.width * $0.height < $1.width * $1.height })?.url.map({($0, d)}) {
                return [result]
            }
        }
        if let result = child.preview?.images?.first?.source?.url.map({($0, d)}) {
            return [result]
        }
        return []
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
        let doc = try decoder.decode(SubredditPage.self, from: json)
        return (doc.data.children.map { $0.data }, doc.data.after)
        
    } catch let err {
        print(err)
    }
    return ([], nil)
}



class RedditLoader: AbstractImageLoader {

    static var sharedExternalDB: DBWrapper!
    static var sharedInternalDB: DBWrapper!
    
    typealias EntityKind = LoadableImageEntity
    typealias VideoDownloadTask = (URL, URLSessionTask)
    let name: String
    let session: URLSession
    let redditSession: URLSession
    let fileManager = FileManager()
    var cacheFunc: ((URL) -> URL?)

    let sqlite : DBWrapper
    let useExternalStorage: Bool
    var cachePath: String
    var videoTasks = [VideoDownloadTask]()
    var ongoingVideoTasks = [VideoDownloadTask]()
    var ongoingVideoTasksLock: DispatchSemaphore
    init(name: String, session: URLSession, external: Bool = false) {
        self.ongoingVideoTasksLock = DispatchSemaphore(value: 1)
        self.name = name
        self.useExternalStorage = external
        self.session = session
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        print("default http max conn per host: \(configuration.httpMaximumConnectionsPerHost) -> 5")
        configuration.httpMaximumConnectionsPerHost = 5
        self.redditSession = URLSession(configuration: configuration)
        if external {
            if RedditLoader.sharedExternalDB == nil {
                RedditLoader.sharedExternalDB = try! DBWrapper(external: true)
            }
            self.sqlite = RedditLoader.sharedExternalDB
            self.cachePath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/.external/\(name)/"
        } else {
            if RedditLoader.sharedInternalDB == nil {
                RedditLoader.sharedInternalDB = try! DBWrapper(external: false)
            }
            self.sqlite = RedditLoader.sharedInternalDB
            self.cachePath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/reddit/\(name)/"
        }
        self.cacheFunc = { (url: URL) -> URL?  in
            let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            let fileName = url.lastPathComponent
            
            if url.host?.contains("v.redd.it") ?? false || (url.host?.contains("preview.redd.it") ?? false && url.query?.contains("format=mp4") ?? false) {
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

    override func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) -> ()) {
        let downPath = self.cachePath + ".json"
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
    
    // Call this in Main Thread
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, attributes: [String: Any], completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        // Note: Such configuration requires that .redd.it domains added to /etc/hosts
//        let useRedditSession = false // url.host!.hasSuffix(".redd.it") ||
//            url.host!.hasSuffix(".redditmedia.com")
        let useRedditSession = url.host!.hasSuffix(".redd.it") 
        let s = useRedditSession ? redditSession : session
        //let fileName = url.lastPathComponent
        let isVideoTask = url.pathExtension == "mp4" || url.pathExtension == "gif"
        let task = s.downloadTask(with: url) { [weak self] (fileUrl, response, err) in
            guard let self = self else {return}
            if let err = err {
                print("[\(self.name)] error loading \(url.absoluteString): \(err.localizedDescription)")
            }
            self.ongoingVideoTasksLock.wait()
            for (tIdx, t) in self.ongoingVideoTasks.enumerated() {
                if t.0 == url {
                    self.ongoingVideoTasks.remove(at: tIdx)
                    break
                }
            }
            self.ongoingVideoTasksLock.signal()
                        
            defer {
                self.ongoingVideoTasksLock.wait()
                while self.ongoingVideoTasks.count < 3 && !self.videoTasks.isEmpty {
                    let nextTask = self.videoTasks.removeFirst()
                    self.ongoingVideoTasks.append(nextTask)
                    nextTask.1.resume()
                }
                self.ongoingVideoTasksLock.signal()
            }
            if let fileUrl = fileUrl, let cacheFileUrl = cacheFileUrl {
                let contentType = (response as! HTTPURLResponse).allHeaderFields["Content-Type"] as? String
                print("[\(self.name)] did fetch: \(url); " + (contentType.map { "type: " + $0 } ?? ""))
                
                return autoreleasepool(invoking: { ()->() in
                    switch contentType {
                        #if os(macOS)
                    case  "image/jpeg", "image/png", "image/gif":
                        if let d = try? Data(contentsOf: fileUrl) {
                            if let img = NSBitmapImageRep(data: d)?.cgImage {
                                let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                                if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                                    do {
                                        try self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                                    } catch (let err) {
                                        print(err)
                                    }
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
            } else {
                return completion([])
            }
        }
        if isVideoTask {
            self.ongoingVideoTasksLock.wait()
            self.videoTasks.append((url, task))
            while self.ongoingVideoTasks.count < 3 && !self.videoTasks.isEmpty {
                let nextTask = self.videoTasks.removeFirst()
                self.ongoingVideoTasks.append(nextTask)
                nextTask.1.resume()
                print("[\(self.name)] will fetch: \(url); ")
            }
            self.ongoingVideoTasksLock.signal()
            
        } else {
            print("[\(self.name)] will fetch: \(url); ")
            task.resume()
        }
    }
    
    override func loadCachedPlaceHolder(with url: URL, attributes: [String: Any]) -> EntityKind? {
//        return autoreleasepool { () -> EntityKind? in
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
//        }
    }
    
    override func cacheFileUrl(for url: URL) -> URL? {
        return self.cacheFunc(url)
    }
    
    override func loadFirstPage(completion: @escaping ([EntityKind]) -> ()) {
        let firstPageUrl = URL(string: "https://www.reddit.com/r/\(name)/.json")!
        let downPath = self.cachePath + "/.json"
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
        let downPath = self.cachePath + "/.json"
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
        
        let downPath = self.cachePath + ".json"
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
