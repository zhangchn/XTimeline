//
//  ViewController.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    @IBOutlet weak var selectionRectangle : NSView!
    var session: URLSession!
    var name : String!
    var sizeForImage: [URL: CGSize] = [:]
    var toolTips: [IndexPath: String] = [:]
    var selectionCenter: CGPoint = .zero {
        didSet {
            selectionRectangle.frame = CGRect(x: selectionCenter.x - selectionSize/2, y: selectionCenter.y - selectionSize/2, width: selectionSize, height: selectionSize)
        }
    }
    var selectionSize: CGFloat = 100 {
        didSet {
            selectionRectangle.frame = CGRect(x: selectionCenter.x - selectionSize/2, y: selectionCenter.y - selectionSize/2, width: selectionSize, height: selectionSize)
        }
    }
    var imageList : [ImageEntity] = []
    var cacheFunc: ((URL) -> URL?)!
    //@IBOutlet weak var topScrollView: NSScrollView!
    @IBOutlet weak var bottomCollectionView: NSCollectionView!
    @IBOutlet weak var topImageView: NSImageView!
    let itemId =  NSUserInterfaceItemIdentifier.init("thumb")
    
    typealias LoaderType = RedditLoader
    var loader: LoaderType!
    typealias ImageEntity = RedditImageEntity
    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSProxy : "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: 1080,
            kCFNetworkProxiesSOCKSEnable: true,
        ]
        session = URLSession(configuration: configuration)
        
        selectionRectangle.isHidden = true
        selectionRectangle.wantsLayer = true
        selectionRectangle.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        selectionRectangle.layer?.borderWidth = 2
        bottomCollectionView.register(ThumbnailItem.self, forItemWithIdentifier: itemId)
        
        bottomCollectionView.allowsMultipleSelection = false
        bottomCollectionView.isSelectable = true
        
        name = "pics"
        loader = LoaderType(name: name, session: session)
        loader.loadFirstPage { (entities: [ImageEntity]) in
            self.imageList = entities
            DispatchQueue.main.async {
                self.bottomCollectionView!.reloadData()
            }
        }
    }
    var bottomHeight : CGFloat = 0 {
        didSet {
            bottomCollectionView.collectionViewLayout?.invalidateLayout()
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        self.view.window?.acceptsMouseMovedEvents = true
        bottomHeight = bottomCollectionView.bounds.height
    }
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        //print("mouse moved: \(event.deltaX), \(event.deltaY)")
        selectionCenter = topImageView.convert(event.locationInWindow, from: nil)
    }
    
    override func scrollWheel(with event: NSEvent) {
        var amount: CGFloat
        if event.modifierFlags.contains(.shift) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaX
            if event.modifierFlags.contains(.option) {
                amount = delta
            } else {
                amount = delta * 16
            }
        } else {
            amount = event.scrollingDeltaY * 4
        }
        selectionSize = max(min(1024, selectionSize + amount), 24)
    }
}

extension ViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageList.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        print("item for indexPath \(indexPath.item)")
        let item = collectionView.makeItem(withIdentifier: itemId, for: indexPath)
        let originalEntity = imageList[indexPath.item]
        if let imageView = item.imageView {
            imageView.toolTip = nil
            switch imageList[indexPath.item] {
                
            case .batchPlaceHolder(let b):
                originalEntity.load(loader: loader) { (entities) in
                    if entities.count > 1 {
                        var indexPaths = Set<IndexPath>()
                        for x in 0..<entities.count {
                            indexPaths.insert(IndexPath(item: indexPath.item + x, section: indexPath.section))
                        }
                        let idx = indexPath.item
                        DispatchQueue.main.async {
                            self.bottomCollectionView.performBatchUpdates({
                                self.imageList.replaceSubrange(idx..<(idx + 1), with: entities)
                                self.bottomCollectionView.deleteItems(at: [indexPath])
                                self.bottomCollectionView.insertItems(at: indexPaths)
                            }, completionHandler: nil)
                        }
                        
                    } else if entities.count == 1{
                        switch entities.first! {
                        case .placeHolder, .image:
                            DispatchQueue.main.async {
                                self.imageList[indexPath.item] = entities.first!
                                self.bottomCollectionView!.reloadItems(at: [indexPath])
                            }
                            
                        case .batchPlaceHolder(let b):
                            self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, false)
                            break
                        }
                    } else {
                        self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, false)
                    }
                }
                switch imageList[indexPath.item] {
                case .batchPlaceHolder:
                    imageView.image = nil
                    imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, true)
                default:
                    break
                }
                imageView.toolTip = "Loading..."
            case .image(let cacheUrl):
                imageView.image = NSImage(contentsOf: cacheUrl)
                imageView.toolTip = self.toolTips[indexPath]
                
            case .placeHolder(let p):
                self.toolTips[indexPath] = p.0.lastPathComponent
                imageView.toolTip = self.toolTips[indexPath]
                originalEntity.load(loader: loader) { (entities) in
                    guard !entities.isEmpty else {
                        self.imageList[indexPath.item] = ImageEntity.placeHolder(p.0, false)
                        return
                    }
                    switch entities.first! {
                    case .image:
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = entities.first!
                            self.bottomCollectionView.reloadItems(at: [indexPath])
                        }
                    default:
                        self.imageList[indexPath.item] = ImageEntity.placeHolder(p.0, false)
                        
                    }
                }
                switch imageList[indexPath.item] {
                case .placeHolder:
                    // if cache is hit, the entity in imageList might have been changed!
                    // skip the following lines
                    imageView.image = nil
                    imageList[indexPath.item] = ImageEntity.placeHolder(p.0, true)
                    
                default:
                    break
                }
                break
            }
            
        }
        return item
    }
}

extension ViewController: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        let layout = collectionViewLayout as! NSCollectionViewFlowLayout
        let margin = layout.sectionInset.top + layout.sectionInset.bottom + 4
        switch imageList[indexPath.item] {
        case .image(let i):
            let imageSize: CGSize? = sizeForImage[i] ?? NSImage(contentsOf: i)?.size
            if let s = imageSize {
                sizeForImage[i] = s
            }
            let height = min(max(collectionView.bounds.height - margin, 20), imageSize?.height ?? 20)
            let width = height * (imageSize?.width ?? 20) / (imageSize?.height ?? 20)
            let size = CGSize(width: width, height: height)
            return size
            
        case .placeHolder, .batchPlaceHolder:
            let height = max(collectionView.bounds.height - margin, 20)
            let size = CGSize(width: height, height: height)
            return size
        }
    }
    /*
     func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
     return indexPaths.filter({ switch imageList[$0.item] { case .image: return true; case .placeHolder, .batchPlaceHolder: return false}})
     }
     */
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let indexPath = indexPaths.first {
            switch imageList[indexPath.item] {
                
            case .image(let image):
                topImageView.image = NSImage(contentsOf: image)
                if let toolTip = toolTips[indexPath] {
                    self.view.window?.title = name + ": " + toolTip
                } else {
                    self.view.window?.title = name + ": ..."
                }
            case .batchPlaceHolder:
                break
            case .placeHolder:
                break
            }
        }
    }
}

extension ViewController: NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        bottomHeight = bottomCollectionView.bounds.height
        
    }
}
