//
//  ThumbViewController.swift
//  XTimeline
//
//  Created by cuser on 2019/2/11.
//  Copyright © 2019 ZhangChen. All rights reserved.
//

import UIKit

class ThumbViewController: UITableViewController {
    typealias ImageEntity = LoadableImageEntity
    var name : String!
    var imageList : [ImageEntity] = []
    typealias LoaderType = AbstractImageLoader
    var loader: LoaderType!
    var session: URLSession!
    var sizeForImage: [URL: CGSize] = [:]

    fileprivate func dynamicSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: 300, height: 300)
        }
        let insets = tableView.safeAreaInsets.left + tableView.safeAreaInsets.right + 32
        let width = min(tableView.bounds.width - insets, imageSize.width)
        let height = width * (imageSize.height) / (imageSize.width)
        return CGSize(width: width, height: height)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:64.0) Gecko/20100101 Firefox/64.0"
        ]
        session = URLSession(configuration: configuration)
        title = name
        
        let fm = FileManager.default
        let downloadPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        var created = fm.fileExists(atPath: downloadPath + "/reddit/.external/" + name)
        if !created {
            let dest = downloadPath + "/reddit/.external/" + name
            do {
                try fm.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
                created = true
            } catch _ {
                
            }
        }
        if !created {
            let path = downloadPath.appending("/reddit/" + name)
            if !fm.fileExists(atPath: path) {
                do {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                } catch let err {
                    let alert = UIAlertController(title: "Error", message: err.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { (_) in
                        alert.dismiss(animated: true, completion: { [weak self] in
                            self?.navigationController?.popViewController(animated: true)
                        })
                    }))
                    present(alert, animated: true, completion: nil)
                    
                    return
                }
            }
        }
        loader = RedditLoader(name: name, session: session)
        loader.loadFirstPage { (entities: [ImageEntity]) in
            self.imageList = entities
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail", let nav = segue.destination as? UINavigationController, let vc = nav.viewControllers.first as? DetailViewController {
            if let indexPath = tableView.indexPathForSelectedRow {
                vc.detailItem = imageList[indexPath.row]
            }
            
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return imageList.count
    }
    
    var generation : UInt = 0

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        let originalEntity = imageList[indexPath.item]
        let previousGeneration = generation
        if let imageView = cell.imageView {
            //imageView.toolTip = nil
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
                                return
                            }
                            self.tableView.beginUpdates()
                            self.imageList.replaceSubrange(idx..<(idx + 1), with: entities)
                            self.tableView.deleteRows(at: [indexPath], with: .automatic)
                            
                            self.tableView.insertRows(at: Array(indexPaths), with: .automatic)
                            self.tableView.endUpdates()
//                            self.bottomCollectionView.performBatchUpdates({
//                                self.imageList.replaceSubrange(idx..<(idx + 1), with: entities)
//                                self.bottomCollectionView.deleteItems(at: [indexPath])
//                                self.bottomCollectionView.insertItems(at: indexPaths)
//                            }, completionHandler: nil)
                        }
                        
                    } else if entities.count == 1{
                        switch entities.first! {
                        case .placeHolder, .image:
                            DispatchQueue.main.async {
                                guard  previousGeneration == self.generation else {
                                    return
                                }
                                self.imageList[indexPath.item] = entities.first!
                                self.tableView.reloadRows(at: [indexPath], with: .none)
                                //self.bottomCollectionView!.reloadItems(at: [indexPath])
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
                    //imageView.toolTip = "Loading..."
                default:
                    // If cache is hit, the entity could have been changed
                    break
                }
            case .image(let (url, cacheUrl, _)):
                if let cacheUrl = cacheUrl {
                    if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                        let thumbUrl = cacheUrl.appendingPathExtension("vthumb")
                        if let thumbnail = UIImage(contentsOfFile: thumbUrl.path) {
                            imageView.image = thumbnail
                        }
                    } else {
                        imageView.image = UIImage(contentsOfFile: cacheUrl.path)
                        let imageSize = self.sizeForImage[url] ?? imageView.image?.size ?? .zero
                        let b = CGRect(origin: .zero, size: dynamicSize(for: imageSize))
                        imageView.frame = b
                        cell.contentView.frame = b
                    }
                }
                //imageView.toolTip = self.toolTips[indexPath]
                
            case .placeHolder(let p):
                //let urlPath = p.0.host?.contains("v.redd.it") ?? false ? p.0.path : p.0.lastPathComponent
                //let author = p.2["author"] as? String ?? ""
                //let title = p.2["title"] as? String ?? ""
                //let selftext = p.2["text"] as? String ?? ""
                //let domain = p.2["domain"] as? String ?? ""
                //let toolTip = domain + ": " + urlPath + "\n" + author + "\n" + title +  (selftext.isEmpty ? "" : ("\n\"\"" + selftext + "\"\"\n"))
                //self.toolTips[indexPath] = toolTip
                //self.shortTips[indexPath] = domain + ": " + urlPath + " " + title
                //imageView.toolTip = toolTip
                loader.load(entity: originalEntity) { (entities) in
                    guard previousGeneration == self.generation else {
                        return
                    }
                    guard !entities.isEmpty else {
                        DispatchQueue.main.async {
                            self.imageList[indexPath.item] = ImageEntity.placeHolder(p.0, false, p.2)
                        }
                        return
                    }
                    switch entities.first! {
                    case .image(let (url, _, attr)):
                        DispatchQueue.main.async {
                            guard previousGeneration == self.generation else {
                                return
                            }
                            self.imageList[indexPath.item] = entities.first!
                            if let size = attr["size"] as? CGSize {
                                self.sizeForImage[url] = size
                            }
                            guard tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false else {
                                return
                            }
                            self.tableView.reloadRows(at: [indexPath], with: .none)
//                            guard collectionView.indexPathsForVisibleItems().contains(indexPath) else {
//                                // Do not trigger re-rendering for invisible cell
//                                return
//                            }
//                            self.bottomCollectionView.reloadItems(at: [indexPath])
                        }
                    default:
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
                    imageList[indexPath.item] = ImageEntity.placeHolder(p.0, true, p.2)
                    
                default:
                    break
                }
                break
            }
            
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        switch imageList[indexPath.item] {
        case .image(let (url, _, attr)):
            if let size = attr["size"] as? CGSize ?? sizeForImage[url] {
                return dynamicSize(for: size).height
            }
        case .placeHolder(let (_, _, attr)):
            if let size = attr["size"] as? CGSize {
                return dynamicSize(for: size).height
            }
        case .batchPlaceHolder:
            break
        }
        return UITableView.automaticDimension
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch imageList[indexPath.item] {
        case .image(let (url, cacheUrl, _)):
            if let cacheUrl = cacheUrl {
                let imageSize: CGSize?
                if cacheUrl.lastPathComponent.hasSuffix(".mp4") {
                    let thumbUrl = cacheUrl.appendingPathExtension("vthumb")
                    let thumbSize = sizeForImage[url] ?? UIImage(contentsOfFile: thumbUrl.path)?.size
                    imageSize = thumbSize
                } else {
                    imageSize = sizeForImage[url] ?? UIImage(contentsOfFile: cacheUrl.path)?.size
                }
                if let s = imageSize {
                    sizeForImage[url] = s
                }
                return dynamicSize(for: imageSize ?? .zero).height
                
            }
        case .placeHolder(let (_, _, attr)):
            if let size = attr["size"] as? CGSize {
                return dynamicSize(for: size).height
            }
        case .batchPlaceHolder:
            break
        }
        return 300
    }
}
