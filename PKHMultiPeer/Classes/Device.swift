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
    var deviceName: String
    /// UUID
    var uuid: String = Device.generateUUID()
    /// peerID
    var peerID: MCPeerID
    /// 连接状态
    var connectStatus: ConnectStatus = .notConnected
    /// 输入流
    var inputStream: InputStream?
    /// 输出流
    var outputStream: OutputStream?
    /// 接收数据
    var receiveData: Data?
    
    /// 格式化设备信息
    /// - Returns: 设备信息
    func formatDict() -> Dictionary<String, String> {
        var retDic: [String: String] = [:]
        retDic["device_name"] = deviceName
        retDic["uuid"] = uuid
        return retDic
    }
    
    static func device(with peerID: MCPeerID, contextInfo info: [String : String]) -> Device? {
        let deviceName: String? = info["device_name"]
        
        guard let newDeviceName = deviceName else {
            return nil
        }
        
        var device = Device(deviceName: newDeviceName, peerID: peerID)
        device.uuid = info["uuid"] ?? Device.generateUUID()
        return device
    }
    
    private static func generateUUID() -> String {
        let uuidString: String = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
        return uuidString
    }
    
}
