//
//  PlainDirLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2022/2/6.
//  Copyright © 2022 ZhangChen. All rights reserved.
//

import Foundation
import Cocoa

class PlainDirLoader: AbstractImageLoader {
    let pathURL: URL
    var batchSize: Int
    let fileManager: FileManager
    var enumerator: FileManager.DirectoryEnumerator?
    
    init(fileUrl: URL, batchSize: Int = 15) {
        self.pathURL = fileUrl
        self.batchSize = batchSize
        self.fileManager = FileManager()
    }
    
    override func loadFirstPage(completion: @escaping ([PlainDirLoader.EntityKind]) -> ()) {
        self.enumerator = fileManager.enumerator(at: pathURL, includingPropertiesForKeys: [.nameKey, .isDirectoryKey])
        if let _ = self.enumerator {
            loadNextBatch(with: pathURL, completion: completion)
        }
    }
    
    override func loadNextBatch(with url: URL, completion: @escaping ([PlainDirLoader.EntityKind]) -> ()) {
        var batchCount = self.batchSize
        var fileItems = [LoadableImageEntity]()
        let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey])
        while batchCount > 0 {
            if let next = enumerator?.nextObject() as? URL {
                guard let resourceValues = try? next.resourceValues(forKeys: resourceKeys), let isDirectory = resourceValues.isDirectory,
                      let name = resourceValues.name else {
                    continue
                }
                if isDirectory {
                    enumerator?.skipDescendants()
                } else {
                    let lowercasedName = name.lowercased()
                    if lowercasedName.hasSuffix(".jpg") || lowercasedName.hasSuffix(".jpeg") || lowercasedName.hasSuffix(".png") {
                        fileItems.append(.placeHolder((next, false, ["name": name])))
                    }
                }
            } else {
                break
            }
            batchCount -= 1
        }
        if batchCount == 0 {
            fileItems.append(.batchPlaceHolder((url, false)))
        }
        return completion(fileItems)
    }
    
    override func loadCachedPlaceHolder(with url: URL, attributes: [String : Any]) -> AbstractImageLoader.EntityKind? {
        if let d = try? Data(contentsOf: url) {
            if let img = NSBitmapImageRep(data: d)?.cgImage {
                let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                var extendedAttr = attributes
                extendedAttr["thumbnail"] = nsImg
                return .image((url, url, extendedAttr))
            }
        }
        return nil
    }
    
    override func cacheFileUrl(for url: URL) -> URL? {
        return url
    }
    
    /*
    override func load(entity: AbstractImageLoader.EntityKind, completion: @escaping ([AbstractImageLoader.EntityKind]) -> ()) {
        switch entity {
        case .placeHolder(let (url, isLoading, attr)):
            if let d = try? Data(contentsOf: url) {
                if let img = NSBitmapImageRep(data: d)?.cgImage {
                    let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                    var extendedAttr = attr
                    extendedAttr["thumbnail"] = nsImg
                    return completion([.image((url, url, extendedAttr))])
                }
            }
        case .image(let (url, _, attr)):
            
        default:
            break
        }
        completion([])
    }
     */
}
