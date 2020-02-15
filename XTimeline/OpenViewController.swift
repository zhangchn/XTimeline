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
    
    override func viewDidLoad() {
        userField.delegate = self
        userField.isAutomaticTextCompletionEnabled = true
    }
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
    var existingText = ""
}

extension OpenViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        let fullString = textView.string
        let beginIndex = fullString.index(fullString.startIndex, offsetBy: charRange.location)
        let endIndex = fullString.index(beginIndex, offsetBy: charRange.length)
        let partialString = String(fullString[beginIndex..<endIndex])
        existingText = partialString
        index[0] = -1
        if (control == self.userField) {
            switch kindSelector.indexOfSelectedItem {
            case 0, 1:
                
                return OfflineRedditLoader.subRedditAutocompletion(for: partialString)
            default:
                return words
            }
        }
        return []
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textView = obj.userInfo?["NSFieldEditor"] as? NSTextView {
            if textView.string == existingText {
                return
            }
            textView.complete(nil)
        }
    }
}
