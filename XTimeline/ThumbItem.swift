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
