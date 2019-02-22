//
//  MasterViewController.swift
//  XTimeline-iOS
//
//  Created by cuser on 2019/2/11.
//  Copyright © 2019 ZhangChen. All rights reserved.
//

import UIKit

class MasterViewController: UITableViewController {

    var detailViewController: DetailViewController? = nil
    var objects = [String]()


    override func viewDidLoad() {
        super.viewDidLoad()
        let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let fm = FileManager()
        if let subs = try? fm.contentsOfDirectory(atPath: p.first!.appending("/reddit")) {
            for sub in subs {
                var isDir : ObjCBool = false
                if fm.fileExists(atPath: p.first! + "/reddit/" + sub , isDirectory: &isDir), isDir.boolValue {
                    objects.append(sub)
                }
            }
        }
        
        // Do any additional setup after loading the view, typically from a nib.
        navigationItem.leftBarButtonItem = editButtonItem

       // let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
       // navigationItem.rightBarButtonItem = addButton
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }

    @objc
    func insertNewObject(_ sender: Any) {
        /*
        objects.insert(NSDate(), at: 0)
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
 */
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "show" {
            if let indexPath = tableView.indexPathForSelectedRow {
                let object = objects[indexPath.row]
                //let controller = (segue.destination as! UINavigationController).topViewController as! ThumbViewController
                let controller = segue.destination as! ThumbViewController
                controller.name = object
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
        if segue.identifier == "add" {
            let vc = segue.destination as! AddViewController
            vc.completionDelegate = self
        }
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return objects.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)

        let object = objects[indexPath.row]
        cell.textLabel!.text = object
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            objects.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }


}

extension MasterViewController : NewItemReceiver {
    
    func didAddNewItem(named name: String) {
        objects.append(name)
        tableView.reloadData()
    }
}