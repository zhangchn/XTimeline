//
//  ThumbItem.swift
//  CropperA
//
//  Created by ZhangChen on 2018/10/2.
//  Copyright © 2018 cuser. All rights reserved.
//

import AppKit

class ThumbnailItem : NSCollectionViewItem {
    required init?(coder: NSCoder) {
        isVideo = false
        super.init(coder: coder)
    }
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        isVideo = false
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    override func prepareForReuse() {
        let f = self.playableIcon.frame
        let r = min(f.size.width, f.size.height)
        self.playableIcon.layer?.cornerRadius = r / 2
        let c = NSColor(deviceWhite: 1.0, alpha: 0.7).cgColor
        self.playableIcon.layer?.backgroundColor = c
    }
    @IBOutlet weak var playableIcon: NSTextField!
    override var isSelected: Bool {
        didSet {
            if isSelected {
                self.imageView?.layer?.borderWidth = 3
                self.imageView?.layer?.borderColor = #colorLiteral(red: 0.2588235438, green: 0.7568627596, blue: 0.9686274529, alpha: 1).cgColor
            } else {
                self.imageView?.layer?.borderWidth = 0
            }
        }
    }
    var isVideo: Bool {
        didSet {
            self.playableIcon.isHidden = !isVideo
            
        }
    }
}


class ThumbItemFilePromiseProvider: NSFilePromiseProvider {
    struct UserInfoKeys {
        static let item = "item"
        static let urlKey = "url"
    }
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(.fileURL)
        return types
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard let userInfoDict = userInfo as? [String: Any] else { return nil }
        switch type {
        case .fileURL:
            if let url = userInfoDict["file-url"] as? NSURL {
                return url.pasteboardPropertyList(forType: type)
            }
        default:
            break
        }
        return super.pasteboardPropertyList(forType: type)
    }
}
