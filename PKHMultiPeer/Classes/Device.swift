//
//  Device.swift
//  PKHMultiPeer
//
//  Created by Pan on 2021/4/22.
//

import UIKit
import MultipeerConnectivity.MCPeerID

public enum ConnectStatus: Int {
    case notConnected = 0       // 空闲
    case connecting = 1         // 连接中
    case connected = 2          // 已连接
}

public enum ConnectFlag: Int {
    case check = 0              // 校验
    case connect = 1            // 连接
}

public struct Device {
    /// 设备名称
    public var deviceName: String
    /// peerID
    public var peerID: MCPeerID
    /// 连接状态
    var connectStatus: ConnectStatus = .notConnected
    /// 输入流
    var inputStream: InputStream?
    /// 输出流
    var outputStream: OutputStream?
    /// 接收数据
    var receiveData: Data?
    
    public init(deviceName: String) {
        self.init(deviceName: deviceName, peerID: Device.generatePeerID())
    }
    
    init(deviceName: String, peerID: MCPeerID) {
        self.deviceName = deviceName
        self.peerID = peerID
    }

    /// 格式化设备信息
    /// - Returns: 设备信息
    func formatDict() -> Dictionary<String, String> {
        var retDic: [String: String] = [:]
        retDic["device_name"] = deviceName
        retDic["uuid"] = peerID.displayName
        return retDic
    }
    
    public static func device(with peerID: MCPeerID, contextInfo info: [String : String]) -> Device? {
        let deviceName: String? = info["device_name"]
        guard let newDeviceName = deviceName else {
            return nil
        }
        
        let device = Device(deviceName: newDeviceName, peerID: peerID)
        return device
    }
    
    static func generatePeerID() -> MCPeerID {
        let peerIDCachekey = "PKHMultiPeerPeerID"
        let peerIDData = UserDefaults.standard.data(forKey: peerIDCachekey)
        
        if let peerIDData = peerIDData {
            let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? MCPeerID
            guard let newPeerID = peerID else {
                fatalError("restore peerID failure")
            }
            return newPeerID
        }else {
            let uuidString: String = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
            let peerID = MCPeerID(displayName: uuidString)
            
            let peerIDData = NSKeyedArchiver.archivedData(withRootObject: peerID)
            UserDefaults.standard.setValue(peerIDData, forKey: peerIDCachekey)
            UserDefaults.standard.synchronize()
            return peerID
        }
    }
    
}
