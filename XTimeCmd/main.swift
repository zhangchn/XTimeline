//
//  main.swift
//  XTimeCmd
//
//  Created by ZhangChen on 2022/3/15.
//  Copyright © 2022 ZhangChen. All rights reserved.
//

import Foundation

let arguments = ProcessInfo.processInfo.arguments

// let names = arguments.suffix(from: 1)
var names = [String]()
var maxCount = 0
var skipOne = false
var shouldLoadVideo = false
if arguments.count > 2 {
    for argPair in zip(arguments.prefix(upTo: arguments.count - 1).suffix(from: 1), arguments.suffix(from: 2)) {
        if skipOne {
            skipOne = false
            continue
        }
        if argPair.0.hasPrefix("-") {
            switch argPair.0 {
            case "-n":
                maxCount = Int(argPair.1) ?? 0
                skipOne = true
            case "-v":
                shouldLoadVideo = true
            default:
                break
            }
        } else {
            names.append(argPair.0)
        }
    }
}
if skipOne == false {
    switch arguments.last! {
    case "-v":
        shouldLoadVideo = true
    default:
        names.append(arguments.last!)
    }
}

for n in names {
    print(": \(n)")
}

typealias ImageEntity = LoadableImageEntity
typealias LoaderType = AbstractImageLoader

func batchLoad(with loader: LoaderType, imageList: inout [ImageEntity]) -> Bool {
    if let lastEntity = imageList.last {
        switch lastEntity {
        case .batchPlaceHolder(let (url, _)):
            imageList[imageList.count - 1] = .batchPlaceHolder((url, true))
            // continue loading
            // isLoadingAll = true
            let notification = DispatchSemaphore(value: 0)
            var entities: [ImageEntity] = []
            loader.loadNextBatch(with: url) { entityList in
                entities = entityList
                notification.signal()
            }
            notification.wait()
            guard !entities.isEmpty else {
                return false
            }
            
            let newLastEntity = entities.last!
            let oldCount = imageList.count
            imageList.replaceSubrange((oldCount - 1)..<oldCount, with: entities)
            
            switch newLastEntity {
            case .batchPlaceHolder(let (url2, _)):
                imageList[imageList.count - 1] = .batchPlaceHolder((url2, false))
            default:
                break
            }
            return true
        default:
            break
        }
    }
    return false
}

/*
func setUpRedditLoader(name: String, session: URLSession, offline: Bool = false) -> RedditLoader? {
    let fm = FileManager.default
    let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    var created = fm.fileExists(atPath: downloadPath + "/reddit/.external/" + name)
    let external = created
    if !created {
        let dest = downloadPath + "/reddit/.external/" + name
        do {
            try fm.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
            try fm.createDirectory(atPath: dest + "/.json", withIntermediateDirectories: false, attributes: nil)
            created = true
            _ = RedditLoader.existingSubreddits.insert(name)
        } catch _ {
            
        }
    }
    if !created {
        let path = downloadPath.appending("/reddit/" + name)
        if !fm.fileExists(atPath: path) {
            do {
                try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                _ = RedditLoader.existingSubreddits.insert(name)
                try fm.createDirectory(atPath: path + "/.json", withIntermediateDirectories: false, attributes: nil)
            } catch let err {
                print("\(err)")
                return nil
            }
        }
    }
    let loader : RedditLoader
    if offline {
        loader = OfflineRedditLoader(name: name, session: session, external: external)
    } else {
        loader = RedditLoader(name: name, session: session, external: external)
    }
    /*
    DispatchQueue.global().async {
        self.setUpYolo()
    }
     */
    return loader
}
 */

let configuration = URLSessionConfiguration.default
configuration.httpMaximumConnectionsPerHost = 4
configuration.connectionProxyDictionary = [
    kCFStreamPropertyHTTPSProxyHost: "127.0.0.1",
    kCFStreamPropertyHTTPSProxyPort: 8118,
    kCFStreamPropertyHTTPProxyHost: "127.0.0.1",
    kCFStreamPropertyHTTPProxyPort: 8118,
//            kCFNetworkProxiesSOCKSProxy : "127.0.0.1",
//            kCFNetworkProxiesSOCKSPort: 1080,
//            kCFNetworkProxiesSOCKSEnable: true,
]
configuration.httpAdditionalHeaders = [
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:66.0) Gecko/20100101 Firefox/66.0"
]

let session = URLSession(configuration: configuration)

// var shouldLoadVideo = false
for name in names {
    if let loader = try? RedditLoader.setUpRedditLoader(name: name, session: session) {
        var imageList: [ImageEntity] = []
        let notification = DispatchSemaphore(value: 0)
        
        loader.loadFirstPage { (entities: [ImageEntity]) in
            imageList = entities
            notification.signal()
        }
        notification.wait()
        var count = 0
        repeat {
            count += 1
            if maxCount > 0 && count > maxCount {
                break
            }
        } while batchLoad(with: loader, imageList: &imageList)
        
        for (itemIdx, item) in imageList.enumerated() {
            switch item {
            case .placeHolder(let (url, isLoading, attr)):
                guard !isLoading else {continue}
                if (url.lastPathComponent.hasSuffix("mp4") || url.lastPathComponent.hasSuffix("gif")) && !shouldLoadVideo {
                    continue
                }
                imageList[itemIdx] = ImageEntity.placeHolder((url, true, attr))
                loader.load(entity: item) { (entities) in
                    notification.signal()
                }
                notification.wait()
            default:
                print(item)
                break
            }
        }
    }
}

