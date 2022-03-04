//
//  AddViewController.swift
//  XTimeline
//
//  Created by cuser on 2019/2/12.
//  Copyright © 2019 ZhangChen. All rights reserved.
//

import UIKit

protocol NewItemReceiver {
    func didAddNewItem(named name: String)
}
class AddViewController: UIViewController {
    weak var completionDelegate: (AnyObject & NewItemReceiver)?
    @IBOutlet weak var saveItem: UIBarButtonItem!
    @IBOutlet weak var textField: UITextField!
    @IBAction func save(_ sender: Any) {
        if let t = textField.text, !t.isEmpty {
            completionDelegate?.didAddNewItem(named: t)
            if let p = presentingViewController {
                p.dismiss(animated: true, completion: nil)
            } else if let n = navigationController {
                n.popViewController(animated: true)
            }
        }
    }
    
    override func viewDidLoad() {
        navigationItem.setRightBarButton(saveItem, animated: false)
    }
}
