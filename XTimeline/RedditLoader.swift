//
//  RedditLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa

fileprivate func entities(from json: Data, url: URL) -> [LoadableImageEntity] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    if let doc = try? decoder.decode(RedditLoader.SubredditPage.self, from: json) {
        var results = doc.data.children.compactMap({ (child) -> String? in
            if child.data.isRedditMediaDomain, let url = child.data.url, let domain = child.data.domain, domain.hasSuffix(".redd.it") || domain.hasSuffix(".redditmedia.com") {
                return url
            }
            if let resolutions = child.data.preview?.images?.first?.resolutions {
                return resolutions.max(by: { $0.width * $0.height < $1.width * $1.height })?.url
            }
            return child.data.preview?.images?.first?.source?.url
        }).map {$0.replacingOccurrences(of: "&amp;", with: "&") } .compactMap({URL(string: $0)}).map { LoadableImageEntity.placeHolder($0, false) }
        
        if let after = doc.data.after {
            let path = url.path
            let schema = url.scheme!
            let host = url.host!
            
            let nextUrl = URL(string: "\(schema)://\(host)\(path)?count=25&after=\(after)")!
            results.append(LoadableImageEntity.batchPlaceHolder(nextUrl, false))
        }
        return results
    }
    return []
}

final class RedditLoader: AbstractImageLoader {
    typealias EntityKind = LoadableImageEntity

    let name: String
    let session: URLSession
    let redditSession: URLSession
    let fileManager = FileManager()
    var cacheFunc: ((URL) -> URL?)

    init(name: String, session: URLSession) {
        self.name = name
        self.session = session
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.redditSession = URLSession(configuration: configuration)
        self.cacheFunc = { (url: URL) -> URL?  in
            let downloadPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first!
            let fileName = url.lastPathComponent
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") || fileName.hasSuffix(".gif") {
                let cachePath =  downloadPath + "/reddit/" + name + "/" + fileName
                return URL(fileURLWithPath: cachePath)
            }
            return nil
        }
    }
    struct SubredditPage : Codable {
        let kind: String
        struct VideoPreview: Codable {
            let fallback_url: String?
            let hls_url: String?
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
                let preview: Preview?
                let url: String?
                let domain: String?
                let isRedditMediaDomain: Bool
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
    
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        // Note: Such configuration requires that .redd.it domains added to /etc/hosts
        let useRedditSession = url.host!.hasSuffix(".redd.it") ||
            url.host!.hasSuffix(".redditmedia.com")
        let s = useRedditSession ? redditSession : session
        let task = s.downloadTask(with: url) { (fileUrl, response, err) in
            if let fileUrl = fileUrl, let _ = NSImage(contentsOf: fileUrl) {
                if let cacheFileUrl = cacheFileUrl {
                    let fileName = url.lastPathComponent
                    if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") || fileName.hasSuffix(".gif") {
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        }
                        return completion([EntityKind.image(url, cacheFileUrl)])
                    }
                }
                //return completion([EntityKind.image(image)])
            }
            return completion([])
        }
        task.resume()
    }
    
    override func loadCachedPlaceHolder(with url: URL) -> EntityKind? {
        let cacheFileUrl = cacheFunc(url)
        if let cacheFileUrl = cacheFileUrl {
            if fileManager.fileExists(atPath: cacheFileUrl.path), let _ = NSImage(contentsOf: cacheFileUrl) {
                return EntityKind.image(url, cacheFileUrl)
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
