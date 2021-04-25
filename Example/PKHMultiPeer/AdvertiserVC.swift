//
//  AdvertiserVC.swift
//  PKHMultiPeer_Example
//
//  Created by Pan on 2021/4/25.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import PKHMultiPeer

class AdvertiserVC: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        multiPeer.startMatching()
    }
    
    //MARK: - Lazyload
    lazy var multiPeer: PKHMultiPeer = {
        let multiPeer = PKHMultiPeer(device: Device(deviceName: UIDevice.current.name),
                                     peerType: .advertiser,
                                     serviceType: "multipeer")
        multiPeer.delegate = self
        return multiPeer
    }()

}

extension AdvertiserVC: PKHMultiPeerDelegate {
    
    func receiveInvitation(from device: Device, invitationHandler: @escaping (Bool) -> ()) {
        DispatchQueue.main.async {
            let alertVC = UIAlertController(title: device.deviceName, message: "请求连接", preferredStyle: .alert)
            let sureAction = UIAlertAction(title: "同意", style: .default) { (action) in
                invitationHandler(true)
            }
            let closeAction = UIAlertAction(title: "取消", style: .cancel) { (action) in

            }
            alertVC.addAction(sureAction)
            alertVC.addAction(closeAction)

            self.present(alertVC, animated: true, completion: nil)
        }
    }
    
    func connectStateDidChange(from device: Device, state: ConnectStatus) {
        print("设备状态信息改变: \(device), state: \(state)")
    }
    
    func didDisconnect(with device: Device) {
        print("\(device.deviceName)断开连接")
    }
    
}
