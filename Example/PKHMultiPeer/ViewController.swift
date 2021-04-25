//
//  ViewController.swift
//  PKHMultiPeer
//
//  Created by 943147350@qq.com on 04/20/2021.
//  Copyright (c) 2021 943147350@qq.com. All rights reserved.
//

import UIKit
import SnapKit

struct Function: Codable {
    var title: String
    var vcName: String
}

class ViewController: UIViewController {
    
    //MARK: - Property
    private let dataSource = [
        Function(title: "browser", vcName: "BrowserVC"),
        Function(title: "adverser", vcName: "AdvertiserVC")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "PKHMultiPeer"
        
        view.backgroundColor = .white
        
        tableView.reloadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func jumpToVC(classModel: Function) {
        guard let spaceName = Bundle.main.infoDictionary!["CFBundleExecutable"] as? String else {
            print("没有获取到命名空间")
            return
        }
        
        let vcClass: AnyClass? = NSClassFromString(spaceName + "." + classModel.vcName)
        
        guard let classType = vcClass as? UIViewController.Type else {
            print("不是控制器类型")
            return
        }

        let vc = classType.init()
        vc.title = classModel.title
        vc.view.backgroundColor = .white

        navigationController?.pushViewController(vc, animated: true)
    }
    
    //MARK: - Lazyload
    lazy var tableView: UITableView = {
        let tableView = UITableView()
        self.view.addSubview(tableView)
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()

}

extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        cell.textLabel?.text = dataSource[indexPath.row].title
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        jumpToVC(classModel: dataSource[indexPath.row])
    }
    
}

