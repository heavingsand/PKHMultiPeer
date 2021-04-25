//
//  BrowserVC.swift
//  PKHMultiPeer_Example
//
//  Created by Pan on 2021/4/25.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import PKHMultiPeer

class BrowserVC: UIViewController {
    
    //MARK: - Property
    var dataSource: [Device] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        multiPeer.startMatching()
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
    
    lazy var multiPeer: PKHMultiPeer = {
        let multiPeer = PKHMultiPeer(device: Device(deviceName: UIDevice.current.name),
                                     peerType: .browser,
                                     serviceType: "multipeer")
        multiPeer.delegate = self
        return multiPeer
    }()

}

extension BrowserVC: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        cell.textLabel?.text = dataSource[indexPath.row].deviceName
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        multiPeer.requestConnect(to: dataSource[indexPath.row])
    }
    
}

extension BrowserVC: PKHMultiPeerDelegate {
    func didDiscoverDevice(device: Device) {
        if let index = dataSource.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
            dataSource[index] = device
        }else {
            dataSource.append(device)
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func didLostDevice(device: Device) {
        if let index = dataSource.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
            dataSource.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func connectStateDidChange(from device: Device, state: ConnectStatus) {
        print("设备状态信息改变: \(device), state: \(state)")
    }
    
    func didDisconnect(with device: Device) {
        print("\(device.deviceName)断开连接")
    }
    
}
