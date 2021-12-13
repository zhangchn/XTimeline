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
            viewController.dismiss(self)
        case 1:
            viewController.setUpRedditLoader(name: userField.stringValue, offline: true)
            viewController.dismiss(self)
        case 2:
            // viewController.setUpTwitterMediaLoader(name: userField.stringValue)
            let panel = NSOpenPanel()
            panel.allowedFileTypes = ["npz"]
            panel.beginSheetModal(for: view.window!) { response in
                switch response {
                case .OK:
                    self.viewController.dismiss(self)
                    // view
                    print("panel.url: \(panel.urls)")
                    self.viewController.setUpDCGANLoader(key: self.userField.stringValue, file: panel.urls.first!)
                default:
                    break
                }
            }
        default:
            break
        }
        
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
        var result = [String]()
        if (control == self.userField) {
            switch kindSelector.indexOfSelectedItem {
            case 0, 1:
                
                result = RedditLoader.subRedditAutocompletion(for: partialString)
            default:
                result = words
            }
        }
        index[0] = -1
        return result
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textView = obj.userInfo?["NSFieldEditor"] as? NSTextView {
            if textView.string == existingText {
                return
            }
            textView.complete(nil)
        }
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let textView = obj.userInfo?["NSFieldEditor"] as? NSTextView {
            existingText = textView.string
        }
    }
}
