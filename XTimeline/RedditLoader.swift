//
//  RedditLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa

enum RedditImageEntity {
    case image(URL)
    case placeHolder(URL, Bool)
    case batchPlaceHolder(URL, Bool)
}

fileprivate func entities(from json: Data, url: URL) -> [RedditImageEntity] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    if let doc = try? decoder.decode(RedditLoader.SubredditPage.self, from: json) {
        var results = doc.data.children.compactMap({ (child) -> String? in
            if child.data.isRedditMediaDomain, let url = child.data.url, let domain = child.data.domain, domain == "i.redd.it" {
                return url
            }
            if let resolutions = child.data.preview?.images?.first?.resolutions {
                return resolutions.max(by: { $0.width * $0.height < $1.width * $1.height })?.url
            }
            return child.data.preview?.images?.first?.source?.url
        }).map {$0.replacingOccurrences(of: "&amp;", with: "&") } .compactMap({URL(string: $0)}).map { RedditImageEntity.placeHolder($0, false) }
        
        if let after = doc.data.after {
            let path = url.path
            let schema = url.scheme!
            let host = url.host!
            
            let nextUrl = URL(string: "\(schema)://\(host)\(path)?count=25&after=\(after)")!
            results.append(RedditImageEntity.batchPlaceHolder(nextUrl, false))
        }
        return results
    }
    return []
}

class RedditLoader: EntityLoader {
    typealias EntityKind = RedditImageEntity

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
    func loadNextBatch(with url: URL, completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        let task = session.dataTask(with: url) { data, response, err in
            if let data = data {
                return completion(entities(from: data, url: url))
            }
            return completion([])
        }
        task.resume()
    }
    
    func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([RedditLoader.EntityKind]) -> ()) {
        // Note: Such configuration requires that .redd.it domains added to /etc/hosts
        let s = url.host!.hasSuffix(".redd.it") ? redditSession : session
        let task = s.downloadTask(with: url) { (fileUrl, response, err) in
            if let fileUrl = fileUrl, let _ = NSImage(contentsOf: fileUrl) {
                if let cacheFileUrl = cacheFileUrl {
                    let fileName = url.lastPathComponent
                    if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") || fileName.hasSuffix(".gif") {
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        }
                        return completion([EntityKind.image(cacheFileUrl)])
                    }
                }
                //return completion([EntityKind.image(image)])
            }
            return completion([])
        }
        task.resume()
    }
    
    func loadCachedPlaceHolder(with url: URL) -> EntityKind? {
        let cacheFileUrl = cacheFunc(url)
        if let cacheFileUrl = cacheFileUrl {
            if fileManager.fileExists(atPath: cacheFileUrl.path), let _ = NSImage(contentsOf: cacheFileUrl) {
                return EntityKind.image(cacheFileUrl)
            }
        }
        return nil
    }
    
    func cacheFileUrl(for url: URL) -> URL? {
        return self.cacheFunc(url)
    }
    
    func loadFirstPage(completion: @escaping ([EntityKind]) -> () ){
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

extension RedditImageEntity: EntityType {
    
    typealias LoaderType = RedditLoader
    func load(loader: LoaderType, completion: @escaping ([LoaderType.EntityKind]) ->()) {
        switch self {
        case .image:
            return completion([self])
        case .batchPlaceHolder(let (url, loading)):
            if loading {
                return
            }
            loader.loadNextBatch(with: url, completion: completion)
        case .placeHolder(let(url, loading)):
            if loading {
                return
            }
            let cacheFileUrl = loader.cacheFileUrl(for: url)
            if let entity = loader.loadCachedPlaceHolder(with: url) {
                return completion([entity])
            }
            loader.loadPlaceHolder(with: url, cacheFileUrl: cacheFileUrl, completion: completion)
        }
    }
}
