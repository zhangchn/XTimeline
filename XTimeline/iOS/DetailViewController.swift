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
    @IBOutlet weak var scrollView: UIScrollView!
    weak var playerController: AVPlayerViewController!
    @IBOutlet weak var widthConstraint: NSLayoutConstraint!
    @IBOutlet weak var heightConstraint: NSLayoutConstraint!
    func configureView() {
        // Update the user interface for the detail item.
        if let detail = detailItem {
            var title = ""
            var text = ""
            if let label = detailDescriptionLabel {
                switch detail {
                case .image(let (_, cacheUrl, attr)):
                    if let t = attr["title"] as? String {
                        title = t
                    }
                    if let d =  attr["text"] as? String {
                        text = d
                    }
                    if let cacheUrl = cacheUrl {
                        let ext = cacheUrl.pathExtension
                        switch ext {
                        case "jpg", "png", "gif", "jpeg":
                            imageView.image = UIImage(contentsOfFile: cacheUrl.path)
                            playerController?.view.isHidden = true
                            scrollView.isHidden = false
                            let size = imageView.image!.size
                            let ratio = size.width / view.bounds.width
                            let minRatio = max(0.05, view.bounds.width / size.width)
                            let maxRatio = max(2.0, minRatio)
                            //imageView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: imageView.image!.size.height / ratio)
                            scrollView.maximumZoomScale = maxRatio
                            scrollView.minimumZoomScale = minRatio
                            scrollView.zoomScale = minRatio
                            //scrollView.bounds = imageView.bounds
                            scrollView.contentSize = imageView.image!.size
                            widthConstraint.constant = imageView.image!.size.width
                            heightConstraint.constant = imageView.image!.size.height
                        case "mp4":
                            playerController?.player = AVPlayer(url: cacheUrl)
                            playerController?.view.isHidden = false
                            //imageView.isHidden = true
                            scrollView.isHidden = true
                        default:
                            break
                        }
                    }
                case .placeHolder(let (_, _, attr)):
                    if let t = attr["title"] as? String {
                        title = t
                    }
                    if let d =  attr["text"] as? String {
                        text = d
                    }
                default:
                    break
                }
                label.text = title + "\n" + text
            }
            
        }
    }

    override func viewDidLoad() {
        
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        configureView()
    }

    var detailItem: LoadableImageEntity? {
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

extension DetailViewController: UIScrollViewDelegate {
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
