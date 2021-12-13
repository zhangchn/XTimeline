//
//  DCGANLoader.swift
//  XTimeline
//
//  Created by ZhangChen on 2021/12/13.
//  Copyright © 2021 ZhangChen. All rights reserved.
//

import Foundation
import simd
import SwiftNpy
import AppKit

class DCGANLoader: AbstractImageLoader {
    var fileURL: URL
    var batchSize: Int
    var loadIndex: Int = 0
    let zippedFileLoader: Npz!
    let key: String
    var imageSize = 56
    var itemCount = -1
    let colorSpace: CGColorSpace!

    init(fileURL: URL, key: String, perBatch size: Int) {
        self.fileURL = fileURL
        self.batchSize = size
        self.key = key
        self.colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
        self.zippedFileLoader = try! Npz(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        if let keyRange = filename.range(of: key) {
            let part = filename[keyRange.upperBound..<filename.endIndex]
            let parts = part.split(separator: ".")
            if parts.count == 3 {
                self.imageSize = Int(parts[0]) ?? 56
                self.itemCount = Int(parts[1]) ?? -1
            }
        }
    }
    
    override func loadFirstPage(completion: @escaping ([AbstractImageLoader.EntityKind]) -> ()) {
        let url = URL(string: "np://?idx=\(loadIndex)&count=\(batchSize)")!
        loadNextBatch(with: url, completion: completion)
    }
    
    override func loadNextBatch(with url: URL, completion: @escaping ([AbstractImageLoader.EntityKind]) -> ()) {
        // parse url
        guard url.scheme == "np" else {
            return completion([])
        }
        let pairs: [(String, Int)] = url.query!.split(separator: "&")
            .compactMap { s -> (String, Int)? in
                let pair = s.split(separator: "=")
                if pair.count == 2, let v = Int(pair[1]) {
                    return (String(pair[0]), v)
                } else {
                    return nil
                }
            }
        let queryDict = Dictionary<String, Int>(uniqueKeysWithValues: pairs)
        if let idx = queryDict["idx"], let count = queryDict["count"] {
            print("shape: \(zippedFileLoader[key]!.shape)")
            var itemBytes: [Int64] = zippedFileLoader[key]!.elements()
            var results = [EntityKind]()
            var buffer = [UInt8](repeating: 0, count: imageSize * imageSize)
            let itemCount = zippedFileLoader[key]!.shape[0] / imageSize / imageSize
            for i in 0..<count {
                if idx + i >= itemCount {
                    break
                }
                let context = itemBytes.withUnsafeBytes { srcPtr -> CGContext? in
                    return buffer.withUnsafeMutableBytes { dstPtr -> CGContext? in
                        for j in 0..<imageSize {
                            for k in 0..<imageSize {
                                dstPtr[k + j * imageSize] = srcPtr[((idx + i) * imageSize * imageSize + j * imageSize + k) * 8]
                            }
                        }
                        return CGContext(data: dstPtr.baseAddress!, width: imageSize, height: imageSize, bitsPerComponent: 8, bytesPerRow: imageSize, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
                    }
                }
                
                
                if let cgImage = context?.makeImage() {
                    let nsImage = NSImage(cgImage: cgImage, size: NSMakeSize(CGFloat(imageSize * 4), CGFloat(imageSize * 4)))
                    var extendedAttr = [String: Any]()
                    extendedAttr["thumbnail"] = nsImage
                    extendedAttr["title"] = "\(idx + i)"
                    extendedAttr["author"] = ""
                    extendedAttr["text"] = ""
                    let url = URL(string: "npy://?idx=\(idx + i)")!
                    results.append(.image((url, url, extendedAttr)))
                }
                
            }
            let resultsCount = results.count
            if !results.isEmpty && idx + resultsCount < itemCount {
                let batchUrl = URL(string: "np://?idx=\(idx + resultsCount)&count=\(count)")!
                print("appending batch placeholder: \(idx + resultsCount)")
                results.append(.batchPlaceHolder((batchUrl, false)))
            }
            return completion(results)
        }
    }
}
