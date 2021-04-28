//
//  PKHMultiPeer.swift
//  PKHMultiPeer
//
//  Created by Pan on 2021/4/22.
//

import UIKit
import MultipeerConnectivity

/// 连接身份
public enum MultiPeerType: String {
    case browser = "browser"                    // 扫描
    case advertiser = "advertiser"              // 广播
}

enum DevicesType {
    case browser
    case connect
}

public protocol PKHMultiPeerDelegate {
    /// 发现设备
    func didDiscoverDevice(_ device: Device)
    
    /// 丢失设备
    func didLostDevice(_ device: Device)
    
    /// 接收到设备的邀请
    func receiveInvitation(from device: Device, invitationHandler:@escaping (_ accpet: Bool) -> ())
    
    /// 设备连接状态改变
    func connectStateDidChange(from device: Device, state: ConnectStatus)
    
    /// 断开设备连接
    func didDisconnect(with device: Device)
    
    /// 收到数据
    func didReceivedData(_ data: Data, form device: Device)
    
    /// 开始接收文件
    func didStartReceivingResource(with resourceName: String, device: Device, progress: Progress)
    
    /// 结束接收文件
    func didFinishReceivingResource(with resourceName: String, device: Device, localURL: URL?, error: Error?)
}

public extension PKHMultiPeerDelegate {
    func didDiscoverDevice(_ device: Device) {}
    
    func didLostDevice(_ device: Device) {}
    
    func receiveInvitation(from device: Device, invitationHandler:(_ accpet: Bool) -> ()) {
        invitationHandler(false)
    }
    
    func connectStateDidChange(from device: Device, state: ConnectStatus) {}
    
    func didDisconnect(with device: Device) {}
    
    func didReceivedData(_ data: Data, form device: Device) {}
    
    func didStartReceivingResource(with resourceName: String, device: Device, progress: Progress) {}
    
    func didFinishReceivingResource(with resourceName: String, device: Device, localURL: URL?, error: Error?) {}
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
    public init(device: Device, peerType: MultiPeerType, serviceType: String) {
        self.myDevice = device
        self.peerType = peerType
        self.serviceType = serviceType
    }
    
    private lazy var session: MCSession = {
        let session = MCSession(peer: self.myDevice.peerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        return session
    }()
    
    private lazy var browser: MCNearbyServiceBrowser = {
        let browser = MCNearbyServiceBrowser(peer: self.myDevice.peerID, serviceType: self.serviceType)
        browser.delegate = self
        return browser
    }()
    
    private lazy var advertiser: MCNearbyServiceAdvertiser = {
        let advertiser = MCNearbyServiceAdvertiser(peer: self.myDevice.peerID,
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
            objc_sync_enter(self)
            browser.startBrowsingForPeers()
            objc_sync_exit(self)
        }
        
        if peerType == .advertiser {
            objc_sync_enter(self)
            advertiser.startAdvertisingPeer()
            objc_sync_exit(self)
        }
    }
    
    /// 结束匹配
    public func stopMatching() {
        if peerType == .browser {
            objc_sync_enter(self)
            browser.stopBrowsingForPeers()
            objc_sync_exit(self)
        }
        
        if peerType == .advertiser {
            objc_sync_enter(self)
            advertiser.stopAdvertisingPeer()
            objc_sync_exit(self)
        }
    }
    
    /// 请求连接
    /// - Parameter device: 设备信息
    public func requestConnect(to device: Device) {
        let context = try! JSONSerialization.data(withJSONObject: myDevice.formatDict(), options: .prettyPrinted)
        browser.invitePeer(device.peerID, to: session, withContext: context, timeout: RequestTimeoutInterval)
        
        reloadDevices(device: device, type: .connect)
    }
    
    /// 断开连接
    public func disconnect() {
        session.disconnect()
    }
    
}

//MARK: - Transmission
extension PKHMultiPeer {
    
    /// 发送data数据
    @discardableResult
    public func sendData(_ data: Data, device: Device) -> Bool {
        do {
            try session.send(data, toPeers: [device.peerID], with: .reliable)
            return true
        } catch {
            MPLog("数据发送出错: \(error)")
            return false
        }
    }
    
    /// 发送资源文件
    public func sendResource(with filePath: String, device: Device) -> Progress? {
        let url = URL(fileURLWithPath: filePath)
        let fileName = url.lastPathComponent
        return session.sendResource(at: url, withName: fileName, toPeer: device.peerID) { (error) in
            MPLog("数据发送: \(String(describing: error))")
        }
    }
    
    /// 发送流数据
    public func sendStream(with data: Data, device: Device) {
        guard let outputStream = device.outputStream,
              outputStream.hasSpaceAvailable,
              outputStream.streamStatus == .open else {
            MPLog("Stream 出错")
            return
        }
        
        dataQueue.async {
            let bytes = data.withUnsafeBytes {
                [UInt8](UnsafeBufferPointer(start: $0, count: data.count))
            }
            outputStream.write([UInt8](data), maxLength: data.count)
        }
    }
    
}

//MARK: - MCSessionDelegate
extension PKHMultiPeer: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        multipeerQueue.async {
            guard var device = self.findDevice(with: peerID.displayName, type: .connect) else {
                MPLog("没有找到对应设备: \(peerID.displayName)")
                return
            }
            
            MPLog("设备状态变更:\(device.deviceName) : \(state.rawValue)")
            
            self.myDevice.connectStatus = ConnectStatus(rawValue: state.rawValue)!
            
            device.connectStatus = ConnectStatus(rawValue: state.rawValue)!
            
            self.delegate?.connectStateDidChange(from: device, state: ConnectStatus(rawValue: state.rawValue)!)
            
            switch state {
            case .notConnected:
                self.removeDevice(with: device.peerID.displayName, type: .connect)
            case .connecting:
                break
            case .connected:
                self.reloadDevices(device: device, type: .connect)
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        dataQueue.async {
            MPLog("获取到一个输入流: \(peerID.displayName)")
            
            if let index = self.connectDevices.firstIndex(where: {$0.peerID.displayName == peerID.displayName}),
               self.connectDevices[index].connectStatus == .connected {
                self.connectDevices[index].inputStream = stream
                self.startStream(stream: stream)
            }
        }
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        MPLog("开始接收文件: \(progress)")
        dataQueue.async {
            if let index = self.connectDevices.firstIndex(where: {$0.peerID.displayName == peerID.displayName}),
               self.connectDevices[index].connectStatus == .connected {
                self.delegate?.didStartReceivingResource(with: resourceName, device: self.connectDevices[index], progress: progress)
            }
        }
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        MPLog("文件接收完毕")
        dataQueue.async {
            if let index = self.connectDevices.firstIndex(where: {$0.peerID.displayName == peerID.displayName}),
               self.connectDevices[index].connectStatus == .connected {
                self.delegate?.didFinishReceivingResource(with: resourceName, device: self.connectDevices[index], localURL: localURL, error: error)
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        dataQueue.sync {
            if let index = self.connectDevices.firstIndex(where: {$0.peerID.displayName == peerID.displayName}),
               self.connectDevices[index].connectStatus == .connected {
                self.delegate?.didReceivedData(data, form: self.connectDevices[index])
            }
        }
    }
}

//MARK: - MCNearbyServiceBrowserDelegate
extension PKHMultiPeer: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        multipeerQueue.async {
            MPLog("foundPeer \(peerID.displayName)")
            
            guard let info = info, let device = Device.device(with: peerID, contextInfo: info) else { return }
            
            self.reloadDevices(device: device, type: .browser)
            
            self.delegate?.didDiscoverDevice(device)
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        multipeerQueue.async {
            MPLog("lostPeer \(peerID.displayName)")
            
            let device = self.findDevice(with: peerID.displayName, type: .browser)
            
            guard let newDevice = device else { return }
            
            self.removeDevice(with: newDevice.peerID.displayName, type: .browser)
            
            self.delegate?.didLostDevice(newDevice)
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

//MARK: - treamDelegate
extension PKHMultiPeer: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        dataQueue.async {
            switch eventCode {
            case .openCompleted:
                MPLog("连接完成")
            case .hasBytesAvailable:
                let index = self.connectDevices.firstIndex(where: { ($0.inputStream?.isEqual(aStream) ?? false) })
                if let newIndex = index {
                    if let inputStream = self.connectDevices[newIndex].inputStream,
                       inputStream.isEqual(aStream) {
                        var buff = [UInt8](repeating: 0, count: 1024)
                        let length = inputStream.read(&buff, maxLength: MemoryLayout.size(ofValue: buff))
                        if length != 0 && length <= MemoryLayout.size(ofValue: buff) {
                            self.connectDevices[newIndex].receiveData?.append(contentsOf: buff)
                        }
                        break
                    }
                    
                }
            case .hasSpaceAvailable:
                MPLog("连接完成")
            case .errorOccurred:
                MPLog("连接完成")
            case .endEncountered:
                MPLog("连接完成")
            default:
                break
            }
        }
    }
}

extension PKHMultiPeer {
    private func reloadDevices(device: Device, type: DevicesType) {
        switch type {
        case .browser:
            objc_sync_enter(self)
            if let index = browseDevices.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
                browseDevices[index] = device
            }else {
                browseDevices.append(device)
            }
            objc_sync_exit(self)
        case .connect:
            objc_sync_enter(self)
            if let index = connectDevices.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
                connectDevices[index] = device
            }else {
                connectDevices.append(device)
            }
            objc_sync_exit(self)
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
            if device.peerID.displayName == uuid {
                return device
            }
        }
        
        return nil
    }
    
    private func removeDevice(with uuid: String, type: DevicesType) {
        switch type {
        case .browser:
            objc_sync_enter(self)
            if let index = browseDevices.firstIndex(where: {$0.peerID.displayName == uuid}) {
                browseDevices.remove(at: index)
            }
            objc_sync_exit(self)
        case .connect:
            objc_sync_enter(self)
            if let index = connectDevices.firstIndex(where: {$0.peerID.displayName == uuid}) {
                connectDevices.remove(at: index)
            }
            objc_sync_exit(self)
        }
    }
    
    private func startStream(stream: Stream) {
        
    }
    
    private func stopStream(stream: Stream) {
        
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


