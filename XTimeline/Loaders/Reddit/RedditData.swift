//
//  RedditData.swift
//  XTimeline
//
//  Created by ZhangChen on 2021/12/30.
//  Copyright © 2021 ZhangChen. All rights reserved.
//

import Foundation

struct SubredditPage : Codable {
    let kind: String
    struct Media: Codable {
        struct Embed: Codable {
            let providerUrl: String?
            let description: String?
            let title: String?
            let thumbnailUrl: String?
            let html: String?
            let type: String?
        }
        
        let type: String?
        let oembed: Embed?
        let redditVideo: VideoPreview?
    }
    struct MediaMetaDataItem: Codable {
        struct SourceItem: Codable {
            let x: Int
            let y: Int
            let u: String?
            let mp4: String?
            let gif: String?
        }
        let status: String
        let m: String? // MIME
        let s: SourceItem?
    }
    struct VideoPreview: Codable {
        let fallbackUrl: String?
        let scrubberMediaUrl: String?
        let hlsUrl: String?
        let duration: Int?
    }
    struct Preview: Codable {
        struct Source: Codable {
            let url: String?
            let width: Int
            let height: Int
        }
        struct Image: Codable {
            let source: Source?
            let resolutions: [Source]?
            let variants: [String: Image]?            
        }
        let images: [Preview.Image]?
        let redditVideoPreview: VideoPreview?
    }
    struct Child: Codable {
        let kind: String
        struct ChildData: Codable {
            
            let author: String?
            let title: String?
            let selftext: String?
            let preview: Preview?
            let url: String?
            let permalink: String?
            let domain: String?
            let isRedditMediaDomain: Bool?
            let isSelf: Bool?
            let media: Media?
            let mediaMetadata: [String: MediaMetaDataItem]?
            let id: String?
            let createdUtc: Int?
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

struct SubredditRemotePage : Codable {
    struct Media: Codable {
        let mime: String
        let url: URL
        let title: String
        let author: String
        let text: String
    }
    let next: URL?
    let media: [Media]
}
