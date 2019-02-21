//
//  DetailViewController.swift
//  XTimeline-iOS
//
//  Created by cuser on 2019/2/11.
//  Copyright © 2019 ZhangChen. All rights reserved.
//

import UIKit
import AVKit

class DetailViewController: UIViewController {

    @IBOutlet weak var detailDescriptionLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    weak var playerController: AVPlayerViewController!
    func configureView() {
        // Update the user interface for the detail item.
        if let detail = detailItem {
            if let label = detailDescriptionLabel {
                label.text = detail.description
            }
        }
    }

    override func viewDidLoad() {
        
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        configureView()
    }

    var detailItem: NSDate? {
        didSet {
            // Update the view.
            configureView()
        }
    }


    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "embed" {
            playerController = segue.destination as? AVPlayerViewController
        }
    }
}

