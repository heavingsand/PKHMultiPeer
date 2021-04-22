//
//  PKHMultiPeer.swift
//  PKHMultiPeer
//
//  Created by Pan on 2021/4/22.
//

import UIKit
import MultipeerConnectivity

/// 连接身份
enum MultiPeerType: String {
    case browser = "browser"                    // 扫描
    case advertiser = "advertiser"              // 广播
}

enum DevicesType {
    case browser
    case invitation
    case connect
}

public protocol PKHMultiPeerDelegate {
    
    /// 接收到设备的邀请
    /// - Parameters:
    ///   - device: 请求设备
    ///   - invitationHandler: 邀请回调
    func receiveInvitation(from device: Device, invitationHandler: @escaping (Bool) -> Void)
}

extension PKHMultiPeerDelegate {
    func receiveInvitation(from device: Device, invitationHandler: @escaping (Bool) -> Void) {
        invitationHandler(false)
    }
}

private let RequestTimeoutInterval: TimeInterval = 15

public class PKHMultiPeer: NSObject {
    //MARK: - Property
    /// 代理
    public var delegate: PKHMultiPeerDelegate?
    /// 本机设备
    private(set) var myDevice: Device
    /// 对等网络类型
    private(set) var peerType: MultiPeerType
    /// 扫描设备列表
    private(set) var browseDevices: [Device] = []
    /// 邀请设备列表
    private(set) var invitationDevices: [Device] = []
    /// 连接设备列表
    private(set) var connectDevices: [Device] = []
    /// 服务类型
    private var serviceType: String
    
    private let multipeerQueue: dispatch_queue_concurrent_t = {
        let multipeerQueue = dispatch_queue_concurrent_t(label: "multipeerQueue")
        return multipeerQueue
    }()
    
    private let streamQueue: dispatch_queue_serial_t = {
        let streamQueue = dispatch_queue_serial_t(label: "streamQueue")
        return streamQueue
    }()
    
    private let dataQueue: dispatch_queue_serial_t = {
        let dataQueue = dispatch_queue_serial_t(label: "dataQueue")
        return dataQueue
    }()
    
    /// 初始化方法
    /// - Parameters:
    ///   - device: 当前设备
    ///   - peerType: 标识扫描端/广播端
    ///   - serviceType: Bonjour services(详见info.plist)
    init(device: Device, peerType: MultiPeerType, serviceType: String) {
        self.myDevice = device
        self.peerType = peerType
        self.serviceType = serviceType
    }
    
    //MARK: - Lazyload
    private lazy var myPeerID: MCPeerID = {
        guard self.myDevice.uuid.count > 0 else {
            fatalError("uuid is empty")
        }
        
        let peerIDData = UserDefaults.standard.data(forKey: self.myDevice.uuid)
        let peerID: MCPeerID?
        
        if let peerIDData = peerIDData, peerIDData.count > 0 {
            peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? MCPeerID
            guard let peerID = peerID else {
                fatalError("restore peerID failure")
            }
            return peerID
        }else {
            peerID = MCPeerID(displayName: self.myDevice.uuid)
            guard let peerID = peerID else {
                fatalError("new peerID failure")
            }
            let newPeerIDData = NSKeyedArchiver.archivedData(withRootObject: peerID)
            UserDefaults.standard.setValue(newPeerIDData, forKey: self.myDevice.uuid)
            UserDefaults.standard.synchronize()
            return peerID
        }
    }()
    
    private lazy var session: MCSession = {
        let session = MCSession(peer: self.myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        return session
    }()
    
    private lazy var browser: MCNearbyServiceBrowser = {
        let browser = MCNearbyServiceBrowser(peer: self.myPeerID, serviceType: self.serviceType)
        browser.delegate = self
        return browser
    }()
    
    private lazy var advertiser: MCNearbyServiceAdvertiser = {
        let advertiser = MCNearbyServiceAdvertiser(peer: self.myPeerID,
                                                   discoveryInfo: self.myDevice.formatDict(),
                                                   serviceType: self.serviceType)
        advertiser.delegate = self
        return advertiser
    }()
}

//MARK: - Scanning/Connect
extension PKHMultiPeer {
    
    /// 开始匹配
    public func startMatching() {
        if peerType == .browser {
            objc_sync_enter(browser)
            browser.startBrowsingForPeers()
            objc_sync_exit(browser)
        }
        
        if peerType == .advertiser {
            objc_sync_enter(advertiser)
            advertiser.startAdvertisingPeer()
            objc_sync_exit(advertiser)
        }
    }
    
    /// 结束匹配
    public func stopMatching() {
        if peerType == .browser {
            objc_sync_enter(browser)
            browser.stopBrowsingForPeers()
            objc_sync_exit(browser)
        }
        
        if peerType == .advertiser {
            objc_sync_enter(advertiser)
            advertiser.stopAdvertisingPeer()
            objc_sync_exit(advertiser)
        }
    }
    
    /// 请求连接
    /// - Parameter device: <#device description#>
    public func requestConnect(device: Device) {
        
    }
    
    public func disconnect() {
        
    }
    
}

//MARK: - MCSessionDelegate
extension PKHMultiPeer: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        
    }
}

//MARK: - MCNearbyServiceBrowserDelegate
extension PKHMultiPeer: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        multipeerQueue.async {
            MPLog("foundPeer \(peerID.displayName)")
            
            guard let info = info else { return }
            
            var device = Device.device(with: peerID, contextInfo: info)
            device.uuid = peerID.displayName
            device.connectFlag = .check
            device.lastBeatTimestamp = Date().timeIntervalSince1970
            
            /// 尝试发起连接校验设备是否可用
            var discoveryInfo = self.myDevice.formatDict()
            discoveryInfo["connect_flag"] = "0"
            let context = try! JSONSerialization.data(withJSONObject: discoveryInfo, options: .prettyPrinted)
            
            self.browser.invitePeer(peerID, to: self.session, withContext: context, timeout: RequestTimeoutInterval)
            
            self.reloadDevices(device: device, type: .invitation)
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        multipeerQueue.async {
            MPLog("lostPeer \(peerID.displayName)")
            
            let device = self.findDevice(with: peerID.displayName, type: .browser)
            
            guard let newDevice = device else { return }
            
            objc_sync_enter(self.browseDevices)
            let index = self.browseDevices.firstIndex(where: {$0.uuid == newDevice.uuid})!
            self.browseDevices.remove(at: index)
            objc_sync_exit(self.browseDevices)
        }
    }
    
}

//MARK: - MCNearbyServiceAdvertiserDelegate
extension PKHMultiPeer: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
    }
    
}

extension PKHMultiPeer {
    private func reloadDevices(device: Device, type: DevicesType) {
        let oldDevice = findDevice(with: device.uuid, type: type)
        
        switch type {
        case .browser:
            if let oldDevice = oldDevice {
                let index = browseDevices.firstIndex(where: {$0.uuid == oldDevice.uuid})!
                browseDevices[index] = device
            }else {
                browseDevices.append(device)
            }
        case .invitation:
            if let oldDevice = oldDevice {
                let index = invitationDevices.firstIndex(where: {$0.uuid == oldDevice.uuid})!
                invitationDevices[index] = device
            }else {
                invitationDevices.append(device)
            }
        case .connect:
            if let oldDevice = oldDevice {
                let index = connectDevices.firstIndex(where: {$0.uuid == oldDevice.uuid})!
                connectDevices[index] = device
            }else {
                connectDevices.append(device)
            }
        }
    }
    
    private func findDevice(with uuid: String, type: DevicesType) -> Device? {
        let deviceArr: [Device]
        switch type {
        case .browser:
            deviceArr = browseDevices
        case .invitation:
            deviceArr = invitationDevices
        case .connect:
            deviceArr = connectDevices
        }
        
        for device in deviceArr {
            if device.uuid == uuid {
                return device
            }
        }
        
        return nil
    }
}

func MPLog<T>(_ message : T, file: String = #file, funcName: String = #function, lineNum: Int = #line) {
    #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let datestr = formatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        print("[\(datestr)] - [\(fileName)] [第\(lineNum)行] \(message)")
    #endif
}


