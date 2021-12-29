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
            self.view.window?.title = "[" + (loadingItemCount == 0 ? "" : "\(loadingItemCount)/") + "\(imageList.count)" + "] " + name
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
    var itemReloadObserver: AnyObject?
    typealias ImageEntity = LoadableImageEntity
    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.connectionProxyDictionary = [
            kCFStreamPropertyHTTPSProxyHost: "127.0.0.1",
            kCFStreamPropertyHTTPSProxyPort: 8118,
            kCFStreamPropertyHTTPProxyHost: "127.0.0.1",
            kCFStreamPropertyHTTPProxyPort: 8118,
//            kCFNetworkProxiesSOCKSProxy : "127.0.0.1",
//            kCFNetworkProxiesSOCKSPort: 1080,
//            kCFNetworkProxiesSOCKSEnable: true,
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
        bottomCollectionView.delegate = self
        
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(reshowTopInfo))
        doubleClick.numberOfClicksRequired = 2
        topImageView.addGestureRecognizer(doubleClick)
        
        // dragging
        bottomCollectionView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)
        
        // double click
        itemReloadObserver = NotificationCenter.default.addObserver(forName: ThumbnailItem.reloadItem, object: nil, queue: .main) { [weak self] note in
            if let self = self, let thumbItem = note.object as? ThumbnailItem {
                if let indexPath = self.bottomCollectionView.indexPath(for: thumbItem) {
                    let item = self.imageList[indexPath.item]
                        
                    switch item {
                    case .placeHolder(let t1):
                        self.imageList[indexPath.item] = .placeHolder((t1.0, false, t1.2))
                    case .batchPlaceHolder(let t2):
                        self.imageList[indexPath.item] = .batchPlaceHolder((t2.0, false))
                    default:
                        break
                    }
                    self.bottomCollectionView.reloadItems(at: [indexPath])
                }
            }
        }
    }
    
    func setUpDCGANLoader(key: String, file: URL) {
        self.name = "\(file.lastPathComponent)[\(key)]"
        loader = DCGANLoader(fileURL: file, key: key, perBatch: 50)
        loader.loadFirstPage { entities in
            self.imageList = entities
            self.bottomCollectionView.reloadData()
        }
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
                try fm.createDirectory(atPath: dest + "/.json", withIntermediateDirectories: false, attributes: nil)
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
                    try fm.createDirectory(atPath: path + "/.json", withIntermediateDirectories: false, attributes: nil)
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
    
    @IBAction func fetchPlaceholders(_ sender: Any) {
        let previousGeneration = self.generation
        for (itemIdx, item) in self.imageList.enumerated() {
            let indexPath = IndexPath(item: itemIdx, section: 0)
            switch item {
            case .placeHolder(let (url, isLoading, attr)):
                guard !isLoading else {continue}
                guard attr["thumbnailUrl"] == nil else {continue}
                self.imageList[itemIdx] = ImageEntity.placeHolder((url, true, attr))                
                
                
                self.loadingItemCount += 1
                self.loader?.load(entity: item) { (entities) in
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
                            self.imageList[itemIdx] = ImageEntity.placeHolder((url, false, attr))
                        }
                        return
                    }
                    switch entities.first! {
                    case .image(let (url, fileUrl, attr)):
                        DispatchQueue.main.async {
                            guard previousGeneration == self.generation else {
                                debugPrint("generation miss 2: previous \(previousGeneration), now is \(self.generation)")
                                return
                            }
                            self.imageList[itemIdx] = entities.first!
                            guard self.bottomCollectionView.indexPathsForVisibleItems().contains(indexPath) else {
                                // Do not trigger re-rendering for invisible cell
                                if let fileUrl = fileUrl {
                                    if !fileUrl.path.hasSuffix(".mp4") {
                                        var newAttr = attr
                                        newAttr["thumbnailUrl"] = fileUrl
                                        newAttr.removeValue(forKey: "thumbnail")
                                        self.imageList[itemIdx] = .placeHolder((url, false, newAttr))
                                    }
                                }
                                return
                            }
                            let shouldReselect = self.bottomCollectionView.selectionIndexPaths.contains(indexPath)
                            self.bottomCollectionView.reloadItems(at: [indexPath])
                            if shouldReselect {
                                self.bottomCollectionView.deselectAll(nil)
                                self.bottomCollectionView.selectItems(at: [indexPath], scrollPosition: .bottom)
                            }
                        }
                    default:
                        // placeHolder or batchPlaceHolder failed to load
                        debugPrint("fail placeholder at \(indexPath.item)")
                        
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.placeHolder((url, false, attr))
                        }
                    }
                }
                
            default:
                break
            }
        }
    }
    
    var isLoadingAll: Bool = false {
        didSet {
            var placeHolderIsLoading = isLoadingAll
            if let lastEntity = self.imageList.last {
                switch lastEntity {
                case .batchPlaceHolder(let (_, l)):
                    placeHolderIsLoading = placeHolderIsLoading || l
                default:
                    break
                }
            }
            if let submenu = self.view.window?.menu?.item(withTitle: "File")?.submenu {
                if let loadMoreMenuItem = submenu.item(withTag: 102) {
                    loadMoreMenuItem.isHidden = placeHolderIsLoading
                }
                if let loadAllMenuItem = submenu.item(withTag: 100) {
                    loadAllMenuItem.isHidden = placeHolderIsLoading
                }
                if let stopLoadingMenuItem = submenu.item(withTag: 101) {
                    stopLoadingMenuItem.isHidden = !placeHolderIsLoading
                }
            }
            
            
        }
    }
    
    @IBAction
    func startLoadAll(_ sender: Any) {
        if !isLoadingAll {
            isLoadingAll = true
            self.batchLoad(continueLoading: true)
        }
    }
    
    @IBAction
    func loadOnce(_ sender: Any) {
        if !isLoadingAll {
            isLoadingAll = true
            self.batchLoad()
        }
    }
    
    func batchLoad(continueLoading: Bool = false) {
        guard isLoadingAll else { return }
        if let lastEntity = self.imageList.last {
            switch lastEntity {
            case .batchPlaceHolder(let (url, _)):
                self.imageList[self.imageList.count - 1] = .batchPlaceHolder((url, true))
                // continue loading
                // isLoadingAll = true
                self.loader.load(entity: .batchPlaceHolder((url, false))) { entityList in
                    DispatchQueue.main.async {
                        guard !entityList.isEmpty else {
                            return
                        }
                        self.loadingItemCount += 0
                        self.bottomCollectionView.performBatchUpdates({
                            let newLastEntity = entityList.last!
                            let oldCount = self.imageList.count
                            self.imageList.replaceSubrange((oldCount - 1)..<oldCount, with: entityList)
                            self.bottomCollectionView.deleteItems(at: [IndexPath(item: oldCount - 1, section: 0)])
                            var indexPaths = [IndexPath]()
                            for i in (oldCount - 1)..<(oldCount - 1 + entityList.count) {
                                indexPaths.append(IndexPath(item: i, section: 0))
                            }
                            self.bottomCollectionView.insertItems(at: Set(indexPaths))
                            switch newLastEntity {
                            case .batchPlaceHolder(let (url2, _)):
                                self.imageList[self.imageList.count - 1] = .batchPlaceHolder((url2, false))
                                
                            default:
                                break
                            }
                        }, completionHandler: { _ in
                            DispatchQueue.main.async {
                                if (continueLoading) {
                                    self.batchLoad(continueLoading: continueLoading)
                                } else {
                                    self.isLoadingAll = false
                                }
                            }
                        })
                    }
                }
            default:
                DispatchQueue.main.async {
                    self.isLoadingAll = false
                }
                break
            }
        }
        
    }
    @IBAction
    func stopLoading(_ sender: Any) {
        isLoadingAll = false
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
        self.view.window?.delegate = self
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
        bottomCollectionView.deselectAll(nil)
        bottomCollectionView.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .left)
    }
    
    func showTopInfo(_ attr: [String: Any]) {
        topInfoLabel.stringValue = (attr["title"] as! String) + "\nBy: " + (attr["author"] as! String) + "\n" + (attr["text"] as! String)
        reshowTopInfo()
    }
    @objc
    func reshowTopInfo() {
        topInfoLabel.isHidden = false
        topInfoLabel.alphaValue = 0.85
        topInfoLabelTimer?.invalidate()
        topInfoLabelTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false, block: { (_) in
            self.topInfoLabel.isHidden = true
        })

    }
}

extension ViewController {
    @IBAction func copy(_ sender: Any?) {
        if let index = bottomCollectionView.selectionIndexPaths.first {
            let pb = NSPasteboard.general
            pb.declareTypes([.string, .fileContents, .URL, .fileURL, .tiff, .png], owner: self)
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
        // print("item for indexPath \(indexPath.item)")
        let item = collectionView.makeItem(withIdentifier: itemId, for: indexPath)
        (item as? ThumbnailItem)?.isVideo = false
        let originalEntity = imageList[indexPath.item]
        let previousGeneration = generation
        if let imageView = item.imageView {
            imageView.toolTip = nil
            switch imageList[indexPath.item] {
                
            case .batchPlaceHolder(let (batchUrl, _)):
                
                loader.load(entity: originalEntity) { (entities) in
                    guard previousGeneration == self.generation else { return }
                    guard indexPath.item == self.imageList.count - 1 else { return }
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
                                let oldSelection = self.bottomCollectionView.selectionIndexPaths
                                self.bottomCollectionView.deleteItems(at: [indexPath])
                                self.bottomCollectionView.insertItems(at: indexPaths)
                                if oldSelection.count == 1 {
                                    self.bottomCollectionView.deselectAll(nil)
                                    self.bottomCollectionView.selectItems(at: oldSelection, scrollPosition: NSCollectionView.ScrollPosition.bottom)
                                }
                                self.loadingItemCount += 0
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
                                let shouldReselect = self.bottomCollectionView.selectionIndexPaths.contains(indexPath)
                                self.bottomCollectionView!.reloadItems(at: [indexPath])
                                if shouldReselect {
                                    self.bottomCollectionView.deselectAll(nil)
                                    self.bottomCollectionView.selectItems(at: [indexPath], scrollPosition: .bottom)
                                }
                            }
                            
                        case .batchPlaceHolder(let (batchUrl2, _)):
                            DispatchQueue.main.async {
                                self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder((batchUrl2, false))
                            }
                            break
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.batchPlaceHolder((batchUrl, false))
                        }
                    }
                }
                
                imageView.image = nil
                imageList[indexPath.item] = ImageEntity.batchPlaceHolder((batchUrl, true))
                switch imageList[indexPath.item] {
                case .batchPlaceHolder:
                    imageView.image = nil
                    imageList[indexPath.item] = ImageEntity.batchPlaceHolder((batchUrl, true))
                    imageView.toolTip = "Loading..."
                default:
                    // If cache is hit, the entity could have been changed
                    break
                }
            case .image(let (url, cacheUrl, attr)):
                if let cacheUrl = cacheUrl {
                    if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                        // debugPrint("load video thumb at \(indexPath.item)")
                        let thumbUrl = cacheUrl.appendingPathExtension("vthumb")
                        if let thumbnail = NSImage(contentsOf: thumbUrl) {
                            imageView.image = thumbnail
                        }
                        // TODO: add file url to attr for key "thumbnailUrl"

                        (item as? ThumbnailItem)?.isVideo = true
                        //if let tItem = item as? ThumbnailItem { tItem.isVideo = true }
                    } else {
                        // debugPrint("load image thumb at \(indexPath.item)")
                        if let thb: NSImage = attr["thumbnail"] as! NSImage? {
                            imageView.image = thb
                            if url.scheme != "npy" {
                                var reducedAttr = attr
                                reducedAttr.removeValue(forKey: "thumbnail")
                                // file url for image file in subreddit folder
                                reducedAttr["thumbnailUrl"] = cacheUrl
                                // invalidate the cgimage from cache immediately after showing it
                                self.imageList[indexPath.item] = ImageEntity.placeHolder((url, false, reducedAttr))
                            }
                        } else {
                            // fallback
                            imageView.image = NSImage(contentsOf: cacheUrl)
                        }
                    }
                }
                imageView.toolTip = self.toolTips[indexPath]
                
//            case .placeHolder(let p):
            case .placeHolder(let (url, isLoading, attr)):
                let urlPath = url.host?.contains("v.redd.it") ?? false ? url.path : url.lastPathComponent
                let author = attr["author"] as? String ?? ""
                let title = attr["title"] as? String ?? ""
                let selftext = attr["text"] as? String ?? ""
                let domain = attr["domain"] as? String ?? ""
                let toolTip = domain + ": " + urlPath + "\n" + author + "\n" + title +  (selftext.isEmpty ? "" : ("\n\"\"" + selftext + "\"\"\n"))
                self.toolTips[indexPath] = toolTip
                self.shortTips[indexPath] = domain + ": " + urlPath + " " + title
                imageView.toolTip = toolTip
                if !isLoading {
                    DispatchQueue.main.async {
                        self.loadingItemCount += 1
                        
                    }
                }
                self.loader?.load(entity: originalEntity) { (entities) in
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
                            self.imageList[indexPath.item] = ImageEntity.placeHolder((url, false, attr))
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
                            let shouldReselect = self.bottomCollectionView.selectionIndexPaths.contains(indexPath)
                            self.bottomCollectionView.reloadItems(at: [indexPath])
                            if shouldReselect {
                                self.bottomCollectionView.deselectAll(nil)
                                self.bottomCollectionView.selectItems(at: [indexPath], scrollPosition: .bottom)
                            }

                        }
                    default:
                        // placeHolder or batchPlaceHolder failed to load
                        debugPrint("fail placeholder at \(indexPath.item)")

                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.placeHolder((url, false, attr))
                        }
                    }
                }
                switch imageList[indexPath.item] {
                case .placeHolder:
                    // if cache is hit, the entity in imageList might have been changed!
                    // skip the following lines
                    imageView.image = nil
                    //self.loadingItemCount -= 1
                    imageList[indexPath.item] = ImageEntity.placeHolder((url, true, attr))
                    
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
                        if imageUrl.scheme == "npy", let img = attr["thumbnail"] as? NSImage {
                            topImageView.image = img
                        } else if let image = NSImage(contentsOf: cacheUrl) {
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
            case .placeHolder(let (url, isLoading, attr)):
                if let e = self.loader?.loadCachedPlaceHolder(with: url, attributes: attr) {
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
                loader.loadPlaceHolder(with: url, cacheFileUrl: loader.cacheFileUrl(for: url), attributes: [:]) { (es) in
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

extension ViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        for indexPath in indexPaths {
            switch imageList[indexPath.item] {
            case .batchPlaceHolder(_):
                return false
            default:
                break
            }
        }
        return true
    }
    
    func promiseProvider(for cacheUrl: URL) -> ThumbItemFilePromiseProvider? {
        let pathExt = cacheUrl.pathExtension
        guard let typeIdentifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExt as CFString, nil) else {
            return nil
        }
        let provider = ThumbItemFilePromiseProvider(fileType: typeIdentifier.takeRetainedValue() as String, delegate: self)
        provider.userInfo = [ThumbItemFilePromiseProvider.UserInfoKeys.urlKey: cacheUrl]
        return provider
    }
    
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt index: Int) -> NSPasteboardWriting? {
        switch imageList[index] {
        case .batchPlaceHolder(_):
            return nil
        case .image(let (url, cacheUrl, _)):
            guard let cacheUrl = cacheUrl else {return nil}
            guard url.scheme != "npy" else {return nil}
            return promiseProvider(for: cacheUrl)
        
        case .placeHolder(let (url, isLoading, attr)):
            guard !isLoading else {
                debugPrint("still loading")
                return nil
                
            }
            guard let cacheUrl = self.loader?.cacheFileUrl(for: url) else {return nil}
            return promiseProvider(for: cacheUrl)
        }
    }
//    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
//        if operation == .delete, let items = session.draggingPasteboard.pasteboardItems {
//            for pasteboardItem in items {
//                if let photoIdx = pasteboardItem.propertyList(forType: ) as? Int {
//                    let indexPath = IndexPath(item: photoIdx, section: 0)
//
//                }
//            }
//        }
//    }
}

extension ViewController: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        return ((filePromiseProvider.userInfo as! [String: URL])[ThumbItemFilePromiseProvider.UserInfoKeys.urlKey]!).lastPathComponent
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let fm = FileManager()
        let source = ((filePromiseProvider.userInfo as! [String: URL])[ThumbItemFilePromiseProvider.UserInfoKeys.urlKey]!)
        do {
            try fm.copyItem(at: source, to: url)
            completionHandler(nil)
        } catch let error {
            completionHandler(error)
        }
        
    }
    
    
}

//extension ViewController: NSDraggingSource {
//    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
//        switch context {
//        case .outsideApplication:
//            return NSDragOperation.copy
//        case .withinApplication:
//            return NSDragOperation.copy
//
//        @unknown default:
//            fatalError()
//        }
//    }
//}


extension ViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let redditLoader = self.loader as? RedditLoader {
            redditLoader.session.invalidateAndCancel()
            redditLoader.redditSession.invalidateAndCancel()
        }
        self.loader = nil
        if let ob = itemReloadObserver {
            NotificationCenter.default.removeObserver(ob)
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        self.isLoadingAll = !(!(self.isLoadingAll))
    }
}
