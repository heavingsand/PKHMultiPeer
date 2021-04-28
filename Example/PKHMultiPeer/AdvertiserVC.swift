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
    //MARK: - Property
    var progress: Progress?
    var progressAlert: UIAlertController?

    //MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        multiPeer.startMatching()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        multiPeer.stopMatching()
        multiPeer.disconnect()
    }
    
    //MARK: - Lazyload
    lazy var multiPeer: PKHMultiPeer = {
        let multiPeer = PKHMultiPeer(device: Device(deviceName: UIDevice.current.name),
                                     peerType: .advertiser,
                                     serviceType: "multipeer")
        multiPeer.delegate = self
        return multiPeer
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        self.view.addSubview(imageView)
        imageView.snp.makeConstraints { (make) in
            make.top.equalTo(15)
            make.left.right.equalToSuperview()
            make.height.equalTo(400)
        }
        return imageView
    }()
}

extension AdvertiserVC {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let progress = object as? Progress {
            print("传输进度: \(progress.fractionCompleted)")
            DispatchQueue.main.async {
                if progress.fractionCompleted > 0 {
                    self.progressAlert?.message = "传输进度:\(progress.fractionCompleted)"
                }
            }
        }
    }
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
    
    func didReceivedData(_ data: Data, form device: Device) {
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.imageView.image = image
            }
        }
    }
    
    func didStartReceivingResource(with resourceName: String, device: Device, progress: Progress) {
        self.progress = progress
        self.progress?.addObserver(self, forKeyPath: "completedUnitCount", options: .new, context: nil)
        
        DispatchQueue.main.async {
            self.progressAlert = UIAlertController(title: "接收文件", message: "传输进度:0%", preferredStyle: .alert)
            self.present(self.progressAlert!, animated: true, completion: nil)
        }
    }
    
    func didFinishReceivingResource(with resourceName: String, device: Device, localURL: URL?, error: Error?) {
        DispatchQueue.main.async {
            if let newError = error {
                self.progressAlert?.message = "文件传输出错:\(newError)"
                print("数据传输出错: \(newError)")
            }else {
                self.progressAlert?.message = "文件传输完成"
            }
            
            self.progress?.removeObserver(self, forKeyPath: "completedUnitCount", context: nil)
            self.progressAlert?.dismiss(animated: true, completion: nil)
        }
    }
    
}
