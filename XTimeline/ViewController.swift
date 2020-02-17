//
//  ViewController.swift
//  XTimeline
//
//  Created by ZhangChen on 2018/10/7.
//  Copyright © 2018 ZhangChen. All rights reserved.
//

import Cocoa
import AVFoundation
import AVKit

func min(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    return CGPoint(x: min(a.x, b.x), y: min(a.y, b.y))
}

func max(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    return CGPoint(x: max(a.x, b.x), y: max(a.y, b.y))
}

class ViewController: NSViewController {
    @IBOutlet weak var selectionRectangle : NSView!
    var session: URLSession!
    var name : String!
    var sizeForImage: [URL: CGSize] = [:]
    var toolTips: [IndexPath: String] = [:]
    var shortTips: [IndexPath: String] = [:]
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
    var loadingItemCount = 0 {
        didSet {
            self.view.window?.title = (loadingItemCount == 0 ? "" : "(\(loadingItemCount))") + name
        }
    }
    //var cacheFunc: ((URL) -> URL?)!
    //@IBOutlet weak var topScrollView: NSScrollView!
    @IBOutlet weak var bottomCollectionView: NSCollectionView!
    @IBOutlet weak var topImageView: NSImageView!
    @IBOutlet weak var topPlayerView: AVPlayerView!
    @IBOutlet weak var topInfoLabel: NSTextField!
    var topInfoLabelTimer: Timer?
    let itemId =  NSUserInterfaceItemIdentifier.init("thumb")
    
    typealias LoaderType = AbstractImageLoader
    var loader: LoaderType!
    typealias ImageEntity = LoadableImageEntity
    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSProxy : "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: 1080,
            kCFNetworkProxiesSOCKSEnable: true,
        ]
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:64.0) Gecko/20100101 Firefox/64.0"
        ]

        session = URLSession(configuration: configuration)
        
        selectionRectangle.isHidden = true
        //selectionRectangle.wantsLayer = true
        selectionRectangle.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        selectionRectangle.layer?.borderWidth = 2
        bottomCollectionView.register(ThumbnailItem.self, forItemWithIdentifier: itemId)
        
        bottomCollectionView.allowsMultipleSelection = false
        bottomCollectionView.isSelectable = true
        
    }

    func setUpRedditLoader(name: String, offline: Bool = false) {
        self.name = name
        self.view.window?.title = name
        let fm = FileManager.default
        let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        var created = fm.fileExists(atPath: downloadPath + "/reddit/.external/" + name)
        let external = created
        if !created {
            let dest = downloadPath + "/reddit/.external/" + name
            do {
                try fm.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
                created = true
                _ = RedditLoader.existingSubreddits.insert(name)
            } catch _ {
                
            }
        }
        if !created {
            let path = downloadPath.appending("/reddit/" + name)
            if !fm.fileExists(atPath: path) {
                do {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                    _ = RedditLoader.existingSubreddits.insert(name)
                } catch let err {
                    let alert = NSAlert(error: err)
                    alert.beginSheetModal(for: self.view.window!) { (resp) in
                        self.view.window?.close()
                        return
                    }
                    return
                }
            }
        }
        if offline {
            loader = OfflineRedditLoader(name: name, session: session, external: external)
        } else {
            loader = RedditLoader(name: name, session: session, external: external)
        }
        loader.loadFirstPage { (entities: [ImageEntity]) in
            self.imageList = entities
            DispatchQueue.main.async {
                self.bottomCollectionView!.reloadData()
            }
        }
    }
    
    func setUpTwitterMediaLoader(name: String) {
        self.name = name
        self.view.window?.title = name
        let fm = FileManager.default
        let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        var created = fm.fileExists(atPath: downloadPath + "/twmedia/.external/" + name)
        if !created {
            let dest = downloadPath + "/twmedia/.external/" + name
            do {
                try fm.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
                created = true
            } catch _ {
                
            }
        }
        if !created {
            let path = downloadPath.appending("/twmedia/" + name)
            if !fm.fileExists(atPath: path) {
                do {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                } catch let err {
                    let alert = NSAlert(error: err)
                    alert.beginSheetModal(for: self.view.window!) { (resp) in
                        self.view.window?.close()
                        return
                    }
                    return
                }
            }
        }
        
        loader = TwitterLoader(name: name, session: session)
        loader.loadFirstPage { (entities: [ImageEntity]) in
            self.imageList = entities
            DispatchQueue.main.async {
                self.bottomCollectionView!.reloadData()
            }
        }
    }

    func close() {
        self.view.window?.close()
    }
    var generation : UInt = 0
    @IBAction func reload(_ sender: Any) {
        generation += 1
        loadingItemCount = 0
        if generation == UInt.max {
            generation = 0
        }
        imageList.removeAll()
        bottomCollectionView.reloadData()
        loader.loadFirstPage { (entities: [ImageEntity]) in
            self.imageList = entities
            DispatchQueue.main.async {
                self.bottomCollectionView!.reloadData()
            }
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "open-sheet", let openVC = segue.destinationController as? OpenViewController {
            openVC.viewController = self
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
        
        if loader == nil {
            let identifier = NSStoryboardSegue.Identifier("open-sheet")
            performSegue(withIdentifier: identifier, sender: nil)
        }
    }
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        //print("mouse moved: \(event.deltaX), \(event.deltaY)")
        //let imageRect = topImageView.cell?.drawingRect(forBounds: topImageView.bounds)
        //print("imageRect: \(imageRect)")
        let b = topImageView.bounds
        let minVal = CGPoint(x: selectionSize / 2, y: selectionSize / 2)
        let maxVal = CGPoint(x: b.maxX - selectionSize / 2, y: b.maxY - selectionSize / 2)
        let pos = topImageView.convert(event.locationInWindow, from: nil)
        selectionCenter = min(maxVal, max(minVal, pos))
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
    
    override func moveToBeginningOfLine(_ sender: Any?) {
        // Ctrl + left
        bottomCollectionView.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .left)
    }
    
    override func moveToBeginningOfDocument(_ sender: Any?) {
        // CMD + up
        bottomCollectionView.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .left)
    }
    
    func showTopInfo(_ attr: [String: Any]) {
        topInfoLabel.stringValue = (attr["title"] as! String) + "\nBy: " + (attr["author"] as! String) + "\n" + (attr["text"] as! String)
        topInfoLabel.isHidden = false
        topInfoLabel.alphaValue = 0.85
        topInfoLabelTimer?.invalidate()
        topInfoLabelTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false, block: { (_) in
            self.topInfoLabel.isHidden = true
        })
    }
}

extension ViewController {
    @IBAction func copy(_ sender: Any?) {
        if let index = bottomCollectionView.selectionIndexPaths.first {
            let pb = NSPasteboard.general
            pb.declareTypes([.string, .fileContents, .URL, .fileURL, .tiff], owner: self)
            if let img = self.topImageView.image {
                pb.writeObjects([img])
            }
            switch self.imageList[index.item] {
            case .placeHolder(let (url, _, attr)):
                pb.setString(url.absoluteString, forType: .string)
                pb.setString(url.absoluteString, forType: .URL)
                if let fileUrl = attr["thumbnailUrl"] as? URL {
                    pb.setString(fileUrl.absoluteString, forType: .fileURL)
                }
            case .image(let (url, fileUrl, attr)):
                pb.setString(url.absoluteString, forType: .string)
                pb.setString(url.absoluteString, forType: .URL)
                
                if let fileUrl = fileUrl {
                    pb.setString(fileUrl.path, forType: .fileURL)
                }
                
            case .batchPlaceHolder(let (url, _)):
                pb.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .URL)
            }
        }
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
        (item as? ThumbnailItem)?.isVideo = false
        let originalEntity = imageList[indexPath.item]
        let previousGeneration = generation
        if let imageView = item.imageView {
            imageView.toolTip = nil
            switch imageList[indexPath.item] {
                
            case .batchPlaceHolder(let b):
                
                loader.load(entity: originalEntity) { (entities) in
                    guard previousGeneration == self.generation else { return }
                    if entities.count > 1 {
                        var indexPaths = Set<IndexPath>()
                        for x in 0..<entities.count {
                            indexPaths.insert(IndexPath(item: indexPath.item + x, section: indexPath.section))
                        }
                        let idx = indexPath.item
                        DispatchQueue.main.async {
                            guard  previousGeneration == self.generation else {
                                debugPrint("generation miss 3: previous \(previousGeneration), now is \(self.generation)")
                                return
                            }
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
                                guard  previousGeneration == self.generation else {
                                    debugPrint("generation miss 4: previous \(previousGeneration), now is \(self.generation)")
                                    return
                                }
                                self.imageList[indexPath.item] = entities.first!
                                self.bottomCollectionView!.reloadItems(at: [indexPath])
                            }
                            
                        case .batchPlaceHolder(let b):
                            DispatchQueue.main.async {
                                self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, false)
                            }
                            break
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, false)
                        }
                    }
                }
                
                imageView.image = nil
                imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, true)
                switch imageList[indexPath.item] {
                case .batchPlaceHolder:
                    imageView.image = nil
                    imageList[indexPath.item] = ImageEntity.batchPlaceHolder(b.0, true)
                    imageView.toolTip = "Loading..."
                default:
                    // If cache is hit, the entity could have been changed
                    break
                }
            case .image(let (url, cacheUrl, attr)):
                if let cacheUrl = cacheUrl {
                    if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                        debugPrint("load video thumb at \(indexPath.item)")
                        let thumbUrl = cacheUrl.appendingPathExtension("vthumb")
                        if let thumbnail = NSImage(contentsOf: thumbUrl) {
                            imageView.image = thumbnail
                        }
                        // TODO: add file url to attr for key "thumbnailUrl"

                        (item as? ThumbnailItem)?.isVideo = true
                        //if let tItem = item as? ThumbnailItem { tItem.isVideo = true }
                    } else {
                        debugPrint("load image thumb at \(indexPath.item)")
                        if let thb: NSImage = attr["thumbnail"] as! NSImage? {
                            imageView.image = thb
                            var reducedAttr = attr
                            reducedAttr.removeValue(forKey: "thumbnail")
                            // file url for image file in subreddit folder
                            reducedAttr["thumbnailUrl"] = cacheUrl
                            // invalidate the cgimage from cache immediately after showing it
                            self.imageList[indexPath.item] = ImageEntity.placeHolder(url, false, reducedAttr)
                        } else {
                            // fallback
                            imageView.image = NSImage(contentsOf: cacheUrl)
                        }
                    }
                }
                imageView.toolTip = self.toolTips[indexPath]
                
            case .placeHolder(let p):
                let urlPath = p.0.host?.contains("v.redd.it") ?? false ? p.0.path : p.0.lastPathComponent
                let author = p.2["author"] as? String ?? ""
                let title = p.2["title"] as? String ?? ""
                let selftext = p.2["text"] as? String ?? ""
                let domain = p.2["domain"] as? String ?? ""
                let toolTip = domain + ": " + urlPath + "\n" + author + "\n" + title +  (selftext.isEmpty ? "" : ("\n\"\"" + selftext + "\"\"\n"))
                self.toolTips[indexPath] = toolTip
                self.shortTips[indexPath] = domain + ": " + urlPath + " " + title
                imageView.toolTip = toolTip
                if !p.1 {
                    self.loadingItemCount += 1
                }
                loader.load(entity: originalEntity) { (entities) in
                    guard previousGeneration == self.generation else {
                        debugPrint("generation miss 1: previous \(previousGeneration), now is \(self.generation)")
                        return
                    }
                    DispatchQueue.main.async {
                        self.loadingItemCount -= 1
                    }
                    guard !entities.isEmpty else {
                        // placeHolder failed to load
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.placeHolder(p.0, false, p.2)
                        }
                        return
                    }
                    switch entities.first! {
                    case .image:
                        DispatchQueue.main.async {
                            guard previousGeneration == self.generation else {
                                debugPrint("generation miss 2: previous \(previousGeneration), now is \(self.generation)")
                                return
                            }
                            self.imageList[indexPath.item] = entities.first!
                            guard collectionView.indexPathsForVisibleItems().contains(indexPath) else {
                                // Do not trigger re-rendering for invisible cell
                                return
                            }
                            self.bottomCollectionView.reloadItems(at: [indexPath])
                        }
                    default:
                        // placeHolder or batchPlaceHolder failed to load
                        debugPrint("fail placeholder at \(indexPath.item)")

                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.placeHolder(p.0, false, p.2)
                        }
                    }
                }
                switch imageList[indexPath.item] {
                case .placeHolder:
                    // if cache is hit, the entity in imageList might have been changed!
                    // skip the following lines
                    imageView.image = nil
                    //self.loadingItemCount -= 1
                    imageList[indexPath.item] = ImageEntity.placeHolder(p.0, true, p.2)
                    
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
        let height = max(collectionView.bounds.height - margin, 20)
        let size = CGSize(width: height, height: height)
        return size
        /*
        let layout = collectionViewLayout as! NSCollectionViewFlowLayout
        let margin = layout.sectionInset.top + layout.sectionInset.bottom + 4
        switch imageList[indexPath.item] {
        case .image(let (url, cacheUrl, _ /* attributes */)):
            //let isVideo = attributes[TwitterLoader.VideoKey] as? Bool ?? false
            if let cacheUrl = cacheUrl {
                let imageSize: CGSize?
                if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                    let thumbUrl = cacheUrl.appendingPathExtension("vthumb")
                    let thumbSize = autoreleasepool {
                        sizeForImage[url] ?? NSImage(contentsOf: thumbUrl)?.size
                    }
                    imageSize = thumbSize
                } else {
                    imageSize =  autoreleasepool {
                        sizeForImage[url] ?? NSImage(contentsOf: cacheUrl)?.size
                    }
                }
                if let s = imageSize {
                    sizeForImage[url] = s
                }
                let height = min(max(collectionView.bounds.height - margin, 30), imageSize?.height ?? 30)
                let width = height * (imageSize?.width ?? 30) / (imageSize?.height ?? 30)
                let size = NSSize(width: width, height: height)
                return size
            }
            return CGSize(width: 20, height: 20)
        case .placeHolder, .batchPlaceHolder:
            let height = max(collectionView.bounds.height - margin, 20)
            let size = CGSize(width: height, height: height)
            return size
        }
         */
    }
    /*
     func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
     return indexPaths.filter({ switch imageList[$0.item] { case .image: return true; case .placeHolder, .batchPlaceHolder: return false}})
     }
     */
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let indexPath = indexPaths.first {
            switch imageList[indexPath.item] {
                
            case .image(let (imageUrl, cacheUrl, attr /*attributes*/)):
                if let cacheUrl = cacheUrl {
                    if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                        topPlayerView.isHidden = false
                        topPlayerView.player = AVPlayer(url: cacheUrl)
                        topPlayerView.player?.play()
                    } else {
                        topPlayerView.player?.pause()
                        topPlayerView.isHidden = true
                        if let image = NSImage(contentsOf: cacheUrl) {
                            topImageView.image = image
                            if cacheUrl.pathExtension == "gif" {
                                topImageView.canDrawSubviewsIntoLayer = true
                                topImageView.animates = true
                            }
                            // TODO: Show textual info and start a timer to hide afterwards
                            showTopInfo(attr)
                        }
                    }
                } else {
                    topImageView.image = NSImage(contentsOf: imageUrl)
                    showTopInfo(attr)
                }
                /*
                if let shortTip = shortTips[indexPath] {
                    self.view.window?.title = name + ": " + shortTip
                } else {
                    self.view.window?.title = name + ": ..."
                }*/
            case .batchPlaceHolder:
                break
            case .placeHolder(let p):
                if let e = loader.loadCachedPlaceHolder(with: p.0, attributes: p.2) {
                    switch e {
                    case .image(let (_, cacheUrl, attributes)):
                        if let img = attributes["thumbnail"] as? NSImage {
                            self.topPlayerView.player?.pause()
                            self.topPlayerView.isHidden = true
                            self.topImageView.image = img
                            if cacheUrl?.pathExtension == "gif" {
                                self.topImageView.canDrawSubviewsIntoLayer = true
                                self.topImageView.animates = true
                            }
                            self.showTopInfo(attributes)
                        }
                    default:
                        break
                    }
                }
                /*
                loader.loadPlaceHolder(with: p.0, cacheFileUrl: loader.cacheFileUrl(for: p.0), attributes: [:]) { (es) in
                    if let e = es.first {
                        switch e {
                        case .image(let (_, cacheUrl, attributes)):
                            if let img = attributes["thumbnail"] as? NSImage {
                                self.topPlayerView.player?.pause()
                                self.topPlayerView.isHidden = true
                                self.topImageView.image = img
                                if cacheUrl?.pathExtension == "gif" {
                                    self.topImageView.canDrawSubviewsIntoLayer = true
                                    self.topImageView.animates = true
                                }
                                
                            }
                        default:
                            break
                        }
                    }
                }
                */
            }
        }
    }
}

extension ViewController: NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        bottomHeight = bottomCollectionView.bounds.height
        
    }
}
