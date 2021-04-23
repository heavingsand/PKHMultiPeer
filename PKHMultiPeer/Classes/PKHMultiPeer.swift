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
    case connect
}

public protocol PKHMultiPeerDelegate {
    /// 发现设备
    /// - Parameter device: 设备信息
    func didDiscoverDevice(device: Device)
    
    /// 丢失设备
    /// - Parameter device: 设备信息
    func didLostDevice(device: Device)
    
    /// 接收到设备的邀请
    /// - Parameters:
    ///   - device: 请求设备
    ///   - invitationHandler: 邀请回调
    func receiveInvitation(from device: Device, invitationHandler:(_ accpet: Bool) -> ())
    
    /// 设备连接状态改变
    /// - Parameters:
    ///   - device: 设备信息
    ///   - state: 连接状态
    func connectStateDidChange(from device: Device, state: ConnectStatus)
    
    /// 断开设备连接
    /// - Parameter device: 设备信息
    func didDisconnect(with device: Device)
}

extension PKHMultiPeerDelegate {
    func didDiscoverDevice(device: Device) {}
    
    func didLostDevice(device: Device) {}
    
    func receiveInvitation(from device: Device, invitationHandler:(_ accpet: Bool) -> ()) {
        invitationHandler(false)
    }
    
    func connectStateDidChange(from device: Device, state: ConnectStatus) {}
    
    func didDisconnect(with device: Device) {}
}

private let ScanTimeOut: TimeInterval = 10                      // 扫描超时时间
private let RequestTimeoutInterval: TimeInterval = 15           // 连接校验时间
private let InvitationTimeOut: TimeInterval = 5                 // 邀请超时时间(用于处理网络缓存)

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
//    private(set) var invitationDevices: [Device] = []
    /// 连接设备列表
    private(set) var connectDevices: [Device] = []
    /// 服务类型
    private var serviceType: String
    
    private let multipeerQueue: dispatch_queue_serial_t = {
        let multipeerQueue = dispatch_queue_serial_t(label: "multipeerQueue")
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
    /// - Parameter device: 设备信息
    public func requestConnect(to device: Device) {
        let context = try! JSONSerialization.data(withJSONObject: myDevice.formatDict(), options: .prettyPrinted)
        browser.invitePeer(device.peerID, to: session, withContext: context, timeout: RequestTimeoutInterval)
        
        reloadDevices(device: device, type: .connect)
    }
    
    public func disconnect() {
        
    }
    
}

//MARK: - MCSessionDelegate
extension PKHMultiPeer: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        multipeerQueue.async {
            guard let device = self.findDevice(with: peerID.displayName, type: .connect) else {
                MPLog("没有找到对应设备: \(peerID.displayName)")
                return
            }
            
            MPLog("设备状态变更:\(device.deviceName) : \(state)")
            
            self.delegate?.connectStateDidChange(from: device, state: ConnectStatus(rawValue: state.rawValue)!)
            
            self.myDevice.connectStatus = ConnectStatus(rawValue: state.rawValue)!
            
            switch state {
            case .notConnected:
                switch self.peerType {
                case .browser:
                    break
                case .advertiser:
                    break
                }
                break
            case .connecting:
                break
            case .connected:
                switch self.peerType {
                case .browser:
                    break
                case .advertiser:
                    break
                }
                break
            }
        }
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
            
            guard let info = info, var device = Device.device(with: peerID, contextInfo: info) else { return }
            
            device.uuid = peerID.displayName
            
            self.reloadDevices(device: device, type: .browser)
            
            self.delegate?.didDiscoverDevice(device: device)
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
            
            self.delegate?.didLostDevice(device: newDevice)
        }
    }
    
}

//MARK: - MCNearbyServiceAdvertiserDelegate
extension PKHMultiPeer: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        multipeerQueue.async {
            guard let context = context,
                  let contextData = try? JSONSerialization.jsonObject(with: context, options: .mutableLeaves),
                  let contextDic = contextData as? [String : String],
                  let device = Device.device(with: peerID, contextInfo: contextDic) else {
                MPLog("设备数据错误")
                invitationHandler(false, self.session)
                return
            }
            
            self.delegate?.receiveInvitation(from: device, invitationHandler: { [weak self] (accept) in
                guard let strongSelf = self else { return }
                if accept {
                    strongSelf.reloadDevices(device: device, type: .connect)
                    invitationHandler(true, strongSelf.session)
                }else {
                    invitationHandler(false, strongSelf.session)
                }
            })
        }
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        MPLog("MCNearbyServiceAdvertiser广播出错 : \(error)")
    }
    
}

extension PKHMultiPeer {
    private func reloadDevices(device: Device, type: DevicesType) {
        let oldDevice = findDevice(with: device.uuid, type: type)
        
        switch type {
        case .browser:
            objc_sync_enter(browseDevices)
            if let oldDevice = oldDevice {
                let index = browseDevices.firstIndex(where: {$0.uuid == oldDevice.uuid})!
                browseDevices[index] = device
            }else {
                browseDevices.append(device)
            }
            objc_sync_exit(browseDevices)
        case .connect:
            objc_sync_enter(connectDevices)
            if let oldDevice = oldDevice {
                let index = connectDevices.firstIndex(where: {$0.uuid == oldDevice.uuid})!
                connectDevices[index] = device
            }else {
                connectDevices.append(device)
            }
            objc_sync_exit(connectDevices)
        }
    }
    
    private func findDevice(with uuid: String, type: DevicesType) -> Device? {
        let deviceArr: [Device]
        switch type {
        case .browser:
            deviceArr = browseDevices
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


