//
//  TwitterLoader.swift
//  CropperA
//
//  Created by ZhangChen on 2018/10/4.
//  Copyright © 2018 cuser. All rights reserved.
//

import Cocoa

final class TwitterLoader: AbstractImageLoader {
    struct TimeLineSnippet: Codable {
        let minPosition: String
        let hasMoreItems: Bool
        let itemsHtml: String
    }

    var cacheFunc: ((URL) -> URL?)

    let name: String
    let session: URLSession
    let fileManager = FileManager()
    init(name: String, session: URLSession) {
        self.name = name
        self.session = session
        self.cacheFunc = { (url: URL) -> URL?  in
            let downloadPath = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first!
            let fileName = url.lastPathComponent
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") {
                let cachePath =  downloadPath + "/" + name + "/" + fileName
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
                        
                        var results = TwitterLoader.imageUrls(from: innerHTML).map { EntityKind.placeHolder($0, false) }
                        
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
    override func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([EntityKind]) ->()) {
        let task = session.downloadTask(with: url) { (fileUrl, response, err) in
            if let fileUrl = fileUrl, let _ = NSImage(contentsOf: fileUrl) {
                if let cacheFileUrl = cacheFileUrl {
                    let fileName = url.lastPathComponent
                    if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".mp4") {
                        if !self.fileManager.fileExists(atPath: cacheFileUrl.path) {
                            try? self.fileManager.copyItem(at: fileUrl, to: cacheFileUrl)
                        }
                        return completion([EntityKind.image(url, cacheFileUrl)])
                    }
                }
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
    
    
    fileprivate func firstPageEntities(html: String) -> [EntityKind] {
        let minId = TwitterLoader.matchPattern1(prefix: "data-min-position=\"", suffix: "\"", in: html).first!
        var results = TwitterLoader.imageUrls(from: html).map { EntityKind.placeHolder($0, false) }
        
        let url = URL(string: "https://twitter.com/i/profiles/show/\(name)/media_timeline?include_available_features=1&include_entities=1&reset_error_state=false&max_position=\(minId)")!
        results.append(EntityKind.batchPlaceHolder(url, false))
        return results
    }
 
    override func loadFirstPage(completion: @escaping ([EntityKind]) -> () ){
        let firstPageUrl = URL(string: "https://twitter.com/\(name)/media")!
        let task = session.dataTask(with: firstPageUrl) {
            (data, response, error) in
            if let data = data, let html = String(data: data, encoding: .utf8) {
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
