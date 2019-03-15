//
//  OpenViewController.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/21.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa

class OpenViewController : NSViewController {
    weak var viewController: ViewController!
    @IBOutlet weak var kindSelector: NSPopUpButton!
    @IBOutlet weak var userField: NSTextField!
    
    @IBAction func commit(_ sender: Any) {
        switch kindSelector.indexOfSelectedItem {
        case 0:
            viewController.setUpRedditLoader(name: userField.stringValue)
        case 1:
            viewController.setUpRedditLoader(name: userField.stringValue, offline: true)
        case 2:
            viewController.setUpTwitterMediaLoader(name: userField.stringValue)
        default:
            break
        }
        viewController.dismiss(self)
    }
    
    override func dismiss(_ sender: Any?) {
        super.dismiss(sender)
        self.viewController.close()
    }
}

