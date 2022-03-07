//
//  AppDelegate.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa
import Vision

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {


    var defaultModel: VNCoreMLModel!
    var model: VNCoreMLModel?
    var compiledUrl: URL?
    // var outputDesc: [String:MLFeatureDescription]?
    var selectedFeatureName: String? = "var_944"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        setUpYolo()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func setUpYolo() {
        if #available(macOS 10.15, *) {
            guard let modelUrl = Bundle.main.url(forResource: "best", withExtension: "mlmodelc"), let yoloMLModel = try? MLModel(contentsOf: modelUrl), let defaultModel = try? VNCoreMLModel(for: yoloMLModel) else {
                print("model failed")
                return
            }
            self.defaultModel = defaultModel
        } else {
            // Fallback on earlier versions
            print("core ml not available")
        }
    }
}

