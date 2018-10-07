//
//  AbstractEntityAndLoader.swift
//  CropperA
//
//  Created by ZhangChen on 2018/10/4.
//  Copyright © 2018 cuser. All rights reserved.
//

import Foundation

protocol EntityLoader {
    associatedtype EntityKind : EntityType where EntityKind.LoaderType == Self
    func loadNextBatch(with url: URL, completion: @escaping ([EntityKind]) ->())
    func loadPlaceHolder(with url: URL, cacheFileUrl: URL?, completion: @escaping ([EntityKind]) ->())
    func loadCachedPlaceHolder(with url: URL) -> EntityKind?
    func cacheFileUrl(for url: URL) -> URL?
}

protocol EntityType {
    associatedtype LoaderType: EntityLoader where LoaderType.EntityKind == Self
    func load(loader: LoaderType, completion: @escaping ([Self]) ->())
}
