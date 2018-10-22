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
        if kindSelector.indexOfSelectedItem == 0 {
            viewController.setUpRedditLoader(name: userField.stringValue)
        } else {
            viewController.setUpTwitterMediaLoader(name: userField.stringValue)
        }
        viewController.dismiss(self)
    }
    
}

