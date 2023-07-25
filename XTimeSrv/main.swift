//
//  main.swift
//  XTimeSrv
//
//  Created by ZhangChen on 2022/4/7.
//  Copyright © 2022 ZhangChen. All rights reserved.
//

import Foundation
import NIOCore
import NIO
import NIOHTTP1

print("Hello, World!")

private final class XTimeHandler: ChannelInboundHandler, ChannelOutboundHandler {
    typealias InboundIn = HTTPRequestHead
    typealias OutboundIn = NIOHTTPClientResponseFull
    
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.addHandler(BackPressureHandler()).flatMap { _ in
            channel.pipeline.addHandler(NIOHTTPServerRequestAggregator(maxContentLength: 40960)).flatMap { _ in
                channel.pipeline.addHandler(XTimeHandler())
            }
        }
    }

