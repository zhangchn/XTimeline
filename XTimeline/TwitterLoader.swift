//
//  TwitterLoader.swift
//  CropperA
//
//  Created by ZhangChen on 2018/10/4.
//  Copyright © 2018 cuser. All rights reserved.
//

import Cocoa

final class TwitterLoader: AbstractImageLoader {
    static let VideoKey = "twvideo"
    struct TimeLineSnippet: Codable {
        let minPosition: String
        let hasMoreItems: Bool
        let itemsHtml: String
    }
    
    struct VideoTweetConfig: Codable {
        struct Track: Codable {
            let contentType: String?
            let contentId: String
            let playbackUrl: String?
            let playbackType: String?
            let is360: Bool?
        }
        let track: Track
    }

    // cacheFunc is a function mapping a resource URL to locally cachable file URL
    var cacheFunc: ((URL) -> URL?)

    let name: String
    let session: URLSession
    let fileManager = FileManager()
    init(name: String, session: URLSession) {
        self.name = name
        self.session = session
        self.cacheFunc = { (url: URL) -> URL?  in
            let isVideo = url.host.map { $0 == "api.twitter.com" } ?? false
            let fm = FileManager()
            let downloadPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first!
            let externalExists = fm.fileExists(atPath: downloadPath + "/twmedia/.external/" + name)
            var cachePath: String?
            if isVideo {
                if let tweetId = url.lastPathComponent.split(separator: ".").first {
                    if externalExists {
                        cachePath = downloadPath + "/twmedia/.external/" + name + "/" + tweetId + ".m3u8"
                    } else {
                        cachePath =  downloadPath + "/twmedia/" + name + "/" + tweetId + ".m3u8"
                    }
                }
            } else {
                let fileName = url.lastPathComponent
                if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") {
                    if externalExists {
                        cachePath =  downloadPath + "/twmedia/.external/" + name + "/" + fileName
                    } else {
                        cachePath =  downloadPath + "/twmedia/" + name + "/" + fileName
                    }
                }
            }
            if let cachePath = cachePath {
                return URL(fileURLWithPath: cachePath)
            }
            return nil
        }
    }
    typealias EntityKind = LoadableImageEntity
    
    fileprivate static func imageUrls(from innerHTML: String) -> [URL] {
        let dataImageUrls = matchPattern1(prefix: "data-image-url=\"", suffix: "\"", in: innerHTML)
        return dataImageUrls.compactMap { URL(string: String($0)) }
    }
    
    fileprivate static func mediaUrls(from innerHTML: String) -> [URL] {
        let segments = innerHTML.components(separatedBy: "<li class=\"js-stream-item")
        let urls = segments.compactMap() { (str) -> [URL]? in
            if (str.contains("<div class=\"AdaptiveMedia-video\">")) {
                // tweet-id
                let tweetIds = matchPattern1(prefix: "data-item-id=\"", suffix: "\"", in: str)
                if tweetIds.isEmpty {
                    return nil
                }
                // deal with video later
                if let u = URL(string: "https://api.twitter.com/1.1/videos/tweet/config/\(tweetIds[0]).json") {
                    return [u]
                } else {
                    return nil
                }
            } else if (str.contains("<div class=\"AdaptiveMedia-photoContainer")) {
                return imageUrls(from: str)
            } else {
                return nil
            }
        }
        
        return urls.joined().map { $0 }
    }
    
    fileprivate static func matchPattern1(prefix: String, suffix: String, in string: String) -> [Substring] {
        var matches : [Substring] = []
        let front = string.startIndex
        let end = string.endIndex
        var substr = string[front..<end]
        while !substr.isEmpty {
            guard let loc1 = substr.range(of: prefix) else {
                break
            }
            substr = substr.suffix(from: loc1.upperBound)
            guard let loc2 = substr.range(of: suffix) else {
                break
            }
            matches.append(substr[substr.startIndex..<loc2.lowerBound])
            substr = substr.suffix(from: loc2.upperBound)
        }
        return matches
    }
    
    override func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) ->()) {
        let task = session.dataTask(with: url) { data, response, err in
            if let data = data, let response = response as? HTTPURLResponse {
                var isJson = false
                for (k,v) in response.allHeaderFields {
                    if let k = k as? String, k.lowercased() == "content-type" {
                        if let v = v as? String, v.contains("text/javascript") || v.contains("application/json") {
                            isJson = true
                        }
                    }
                }
                if isJson {
                    do {
                        let dec = JSONDecoder()
                        dec.keyDecodingStrategy = .convertFromSnakeCase
                        let timeline = try dec.decode(TimeLineSnippet.self, from: data)
                        let innerHTML = timeline.itemsHtml
                        
                        //var results = TwitterLoader.imageUrls(from: innerHTML).map { EntityKind.placeHolder($0, false, [:]) }
                        var results = TwitterLoader.mediaUrls(from: innerHTML).map { (url) -> EntityKind in
                            if let host = url.host, host == "api.twitter.com" {
                                return EntityKind.placeHolder(url, false, [TwitterLoader.VideoKey : true])
                            } else {
                                return EntityKind.placeHolder(url, false, [TwitterLoader.VideoKey : false])
                            }
                        }
                        if timeline.hasMoreItems {
                            let query = url.query!.components(separatedBy: "&") .map {
                                $0.starts(with: "max_position=") ? "max_position=\(timeline.minPosition)" : $0
                                } .joined(separator: "&")
                            let nextUrl = URL(string: "\(url.scheme!)://\(url.host!)\(url.path)?\(query)")!
                            results.append(EntityKind.batchPlaceHolder(nextUrl, false))
                        }
                        
                        return completion(results)
                    } catch {
                        print("error decoding json from \(url)")
                        print(String(data: data, encoding: .utf8)!)
                    }
                }
            }
            return completion([])
        }
        task.resume()
    }
    
    func loadVideo(with playbackUrl: URL, cacheFileUrl: URL?, attributes: [String: Any], completion: @escaping([EntityKind])->()) {
        guard let cacheFileUrl = cacheFileUrl else { return }
        let task = self.session.dataTask(with: playbackUrl) { (data, response, err) in
            if let data = data, let str = String(data: data, encoding: String.Encoding.utf8) {
                let lines = str.split(separator: "\n")
                var path: [String] = []
                for idx in 0..<lines.count {
                    let line = lines[idx]
                    if line.hasPrefix("#EXT-X-STREAM-INF:"), idx < lines.count - 1 {
                        path.append(String(lines[idx + 1]))
                    }
                }
                if !path.isEmpty {
                    let p = path.count > 2 ? path[1] : path.last!
                    let url = URL(string: playbackUrl.scheme! + "://" + playbackUrl.host! + p)!
                    
                    let task2 = self.session.dataTask(with: url) { (data2, response2, err2) in
                        if let data2 = data2, let str = String(data: data2, encoding: String.Encoding.utf8) {
                            let out = str.split(separator: "\n").map {
                                $0.hasPrefix("#") ? $0 : (playbackUrl.scheme! + "://" + playbackUrl.host! + $0)
                                } .joined(separator: "\n")
                            try? out.data(using: .utf8)?.write(to: cacheFileUrl)
                        }
                    }
                    task2.resume()
                } else {
                    return completion([])
                }
            }
        }
        task.resume()
    }
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, attributes:[String: Any], completion: @escaping ([EntityKind]) ->()) {
        var req = URLRequest(url: url)
        var isVideo = false
        if let host = url.host, host == "api.twitter.com" {
            isVideo = true
            req.addValue("https://twitter.com/\(name)/media/", forHTTPHeaderField: "Referer")
            req.addValue("", forHTTPHeaderField: "authorization")
            req.addValue("""
""", forHTTPHeaderField: "Cookie")
            req.addValue("", forHTTPHeaderField: "x-csrf-token")
            req.addValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        }
        let task = session.downloadTask(with: req) { (fileUrl, response, err) in
            if isVideo {
                if let fileUrl = fileUrl, let json = try? Data(contentsOf: fileUrl) {
                    let dec = JSONDecoder()
                    do {
                        let config = try dec.decode(VideoTweetConfig.self, from: json)
                        if let u = config.track.playbackUrl, let playbackUrl = URL(string: u) {
                            print("will load (\(config.track.contentId), \(config.track.contentType ?? ""), \(config.track.playbackType ?? ""), \(config.track.playbackUrl ?? ""))")
                            if let type = config.track.playbackType, type == "video/mp4" {
                                // https://video.twimg.com/tweet_video/__ID__.mp4
                                // Recursively load mp4 for gif resources
                                let gifCacheURL = self.cacheFunc(playbackUrl)
                                if let path = gifCacheURL?.path, self.fileManager.fileExists(atPath: path) {
                                    return completion([EntityKind.image(url, gifCacheURL, attributes)])
                                }
                                return self.loadPlaceHolder(with: playbackUrl, cacheFileUrl: gifCacheURL, attributes: attributes, completion: completion)
                            }
                            self.loadVideo(with: playbackUrl, cacheFileUrl: cacheFileUrl, attributes: attributes, completion: completion)
                            return
                        }
                    } catch let err {
                        print("Error decoding video config: \(err)")
                    }
                }
            } else if let fileUrl = fileUrl {
                if let cacheFileUrl = cacheFileUrl {
                    let fileExtension = url.pathExtension.lowercased()
                    switch fileExtension {
                    case "jpg", "png", "gif":
                        if NSImage(contentsOf: fileUrl) == nil {
                            return completion([])
                        }
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        }
                        return completion([EntityKind.image(url, cacheFileUrl, attributes)])
                    case "mp4":
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                            return generateThumbnail(for: url, cacheFileUrl: cacheFileUrl, attributes: attributes, completion: completion)

                        }
                    default:
                        break
                    }
                }
            }
            return completion([])
        }
        task.resume()
    }
    override func loadCachedPlaceHolder(with url: URL, attributes: [String: Any]) -> EntityKind? {
        let cacheFileUrl = cacheFunc(url)
        if let cacheFileUrl = cacheFileUrl {
            if fileManager.fileExists(atPath: cacheFileUrl.path) {
                switch cacheFileUrl.pathExtension {
                case "m3u8":
                    return EntityKind.image(url, cacheFileUrl, attributes)
                case "jpg", "jpeg", "png", "gif":
                    if let _ = NSImage(contentsOf: cacheFileUrl) {
                        return EntityKind.image(url, cacheFileUrl, attributes)
                    }
                case "mp4":
                    let path = cacheFileUrl.path
                    let thumbPath = path + ".vthumb"
                    
                    if !fileManager.fileExists(atPath: thumbPath) {
                        // FIXME: Should reload after thumbnail generation
                        generateThumbnail(for: url, cacheFileUrl: cacheFileUrl, attributes: attributes) { _ in }
                    }
                    return EntityKind.image(url, cacheFileUrl, attributes)
                    
                default:
                    break
                }
                
                
            }
        }
        return nil
    }
    
    
    fileprivate func firstPageEntities(html: String) -> [EntityKind] {
        guard let minId = TwitterLoader.matchPattern1(prefix: "data-min-position=\"", suffix: "\"", in: html).first else {
            return []
        }
        //var results = TwitterLoader.imageUrls(from: html).map { EntityKind.placeHolder($0, false, [:]) }
        var results = TwitterLoader.mediaUrls(from: html).map { EntityKind.placeHolder($0, false, [:]) }

        let url = URL(string: "https://twitter.com/i/profiles/show/\(name)/media_timeline?include_available_features=1&include_entities=1&reset_error_state=false&max_position=\(minId)")!
        results.append(EntityKind.batchPlaceHolder(url, false))
        return results
    }
 
    override func loadFirstPage(completion: @escaping ([EntityKind]) -> () ){
        let firstPageUrl = URL(string: "https://twitter.com/\(name)/media")!
        let task = session.dataTask(with: firstPageUrl) {
            (data, response, error) in
            if let data = data, let html = String(data: data, encoding: .utf8) {
                if html.contains("<div class=\"errorpage-topbar\">") {
                    /*
                     DispatchQueue.main.async {
                     let error = NSError(domain: "twloader", code: 10, userInfo: [NSLocalizedFailureReasonErrorKey: "Invalid URL"])
                     let alert = NSAlert(error: error)
                     alert.beginSheetModal(for: <#T##NSWindow#>, completionHandler: nil)
                     }*/
                    print("Error loading url: \(firstPageUrl)")
                    return completion([])
                }
                
                let imageList = self.firstPageEntities(html: html)
                completion(imageList)
//                DispatchQueue.main.async {
//                    self.bottomCollectionView!.reloadData()
//                }
            }
            
        }
        task.resume()
    }
    
    override func cacheFileUrl(for url: URL) -> URL? {
        return self.cacheFunc(url)
    }
}
