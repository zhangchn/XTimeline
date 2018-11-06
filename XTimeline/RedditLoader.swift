//
//  RedditLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa
import AVFoundation

fileprivate func entities(from json: Data, url: URL) -> [LoadableImageEntity] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    if let doc = try? decoder.decode(RedditLoader.SubredditPage.self, from: json) {
        var results = doc.data.children.compactMap({ (child) -> String? in
            let d = child.data
            if d.isRedditMediaDomain, let url = d.url, let domain = d.domain, domain.hasSuffix(".redd.it") || domain.hasSuffix(".redditmedia.com") {
                if domain.hasSuffix("v.redd.it"), let videoPreview = d.media?.redditVideo {
                    if let scrubberUrl = videoPreview.scrubberMediaUrl {
                        return scrubberUrl
                    }
                    if let fallbackUrl = videoPreview.fallbackUrl {
                        return fallbackUrl
                    }
                }
                return url
            }
            if let videoPreview = d.preview?.redditVideoPreview {
                if let scrubberUrl = videoPreview.scrubberMediaUrl {
                    return scrubberUrl
                }
                if let fallbackUrl = videoPreview.fallbackUrl {
                    return fallbackUrl
                }
            }
            if let resolutions = d.preview?.images?.first?.resolutions {
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
                let cachePath = downloadPath + "/reddit/" + name + "/" + fileName
                return URL(fileURLWithPath: cachePath)
            }
            if url.host?.contains("v.redd.it") ?? false {
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
                let providerUrl: String
                let description: String
                let title: String
                let thumbnailUrl: String
                let html: String
                let type: String
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
                let preview: Preview?
                let url: String?
                let domain: String?
                let isRedditMediaDomain: Bool
                let media: Media?
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
                        return completion([EntityKind.image(url, cacheFileUrl)])
                    }
                case "video/mp4":
                    
                    if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                        
                        try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
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
                                return completion([EntityKind.image(url, cacheFileUrl)])
                            case .failed:
                                return completion([EntityKind.image(url, cacheFileUrl)])
                            default:
                                break
                            }
                        })
                    } else {
                        return completion([EntityKind.image(url, cacheFileUrl)])
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
