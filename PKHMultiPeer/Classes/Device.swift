//
//  Device.swift
//  PKHMultiPeer
//
//  Created by Pan on 2021/4/22.
//

import UIKit
import MultipeerConnectivity.MCPeerID

enum ConnectStatus {
    case idle                       // 空闲
    case connecting                 // 连接中
    case connected                  // 已连接
    case disconnecting              // 断开连接中
}

enum ConnectFlag: Int {
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
    var connectStatus: ConnectStatus = .idle
    /// 输入流
    var inputStream: InputStream?
    /// 输出流
    var outputStream: OutputStream?
    /// 接收数据
    var receiveData: Data?
    /// 连接标志位
    var connectFlag: ConnectFlag = .check
    /// 上次活跃时间
    var lastBeatTimestamp: TimeInterval = 0
    /// 设备邀请回调
    var invitationHandler:((_ accpet: Bool, _ session: MCSession?) -> ())?
    
    /// 格式化设备信息
    /// - Returns: 设备信息
    func formatDict() -> Dictionary<String, String> {
        var retDic: [String: String] = [:]
        retDic["device_name"] = deviceName
        retDic["uuid"] = uuid
        retDic["connect_flag"] = String(connectFlag.rawValue)
        return retDic
    }
    
    static func device(with peerID: MCPeerID, contextInfo info: [String : String]) -> Device {
        let deviceName: String = info["device_name"] ?? ""
        var device = Device(deviceName: deviceName, peerID: peerID)
        device.connectFlag = ConnectFlag(rawValue: Int(info["connect_flag"] ?? "0") ?? 0) ?? .check
        return device
    }
    
    private static func generateUUID() -> String {
        let uuidString: String = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
        return uuidString
    }
    
}
