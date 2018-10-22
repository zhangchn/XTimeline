//
//  AbstractEntityAndLoader.swift
//  CropperA
//
//  Created by ZhangChen on 2018/10/4.
//  Copyright © 2018 cuser. All rights reserved.
//

import Foundation

protocol EntityLoader {
    associatedtype EntityKind : EntityType // where EntityKind.LoaderType == Self
    func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) ->())
    func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([EntityKind]) ->())
    func loadCachedPlaceHolder(with url: URL) -> EntityKind?
    func cacheFileUrl(for url: URL) -> URL?
}

protocol EntityLoading {
    associatedtype EntityKind : EntityType
    func load(entity: EntityKind, completion: @escaping ([EntityKind]) ->())
}

protocol EntityType {
}

enum LoadableImageEntity: EntityType {
    case image(URL, URL?) // URL and cache file URL if exists
    case placeHolder(URL, Bool)
    case batchPlaceHolder(URL, Bool)
}

class AbstractImageLoader: EntityLoader, EntityLoading {
    typealias EntityKind = LoadableImageEntity
    
    func loadFirstPage(completion: @escaping ([EntityKind]) -> ()) {
        
    }
    func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) -> ()) {
        
    }
    
    func cacheFileUrl(for url: URL) -> URL? {
        return nil
    }
    
    func loadCachedPlaceHolder(with url: URL) -> AbstractImageLoader.EntityKind? {
        return nil
    }
    
    func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([AbstractImageLoader.EntityKind]) -> ()) {
        
    }
    
    func load(entity: EntityKind, completion: @escaping ([EntityKind]) -> ()) {
        switch entity {
        case .image:
            return completion([entity])
        case .batchPlaceHolder(let (url, loading)):
            if loading {
                return
            }
            self.loadNextBatch(with: url, completion: completion)
        case .placeHolder(let(url, loading)):
            if loading {
                return
            }
            let cacheFileUrl = self.cacheFileUrl(for: url)
            if let entity = self.loadCachedPlaceHolder(with: url) {
                return completion([entity])
            }
            self.loadPlaceHolder(with: url, cacheFileUrl: cacheFileUrl, completion: completion)
            
        }
    }
}
