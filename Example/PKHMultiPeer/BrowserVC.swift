//
//  BrowserVC.swift
//  PKHMultiPeer_Example
//
//  Created by Pan on 2021/4/25.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import PKHMultiPeer
import AVFoundation

public var kSafaArea: UIEdgeInsets {
    get {
        if #available(iOS 11.0, *) {
            return UIApplication.shared.delegate?.window??.safeAreaInsets ?? UIEdgeInsets.zero
        } else {
            return UIEdgeInsets.zero
        }
    }
}

class BrowserVC: UIViewController {
    
    //MARK: - Property
    var dataSource: [Device] = []
    var captureDevice: AVCaptureDevice?
    var deviceInput: AVCaptureDeviceInput?
    var videoOutput: AVCaptureVideoDataOutput?
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var connectDevice: Device?
    var isStartVideo: Bool = false

    //MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        settingCamera()
        fileBtn.setTitle("传输文件", for: .normal)
        videoBtn.setTitle("传输视频", for: .normal)
        dataBtn.setTitle("传输数据", for: .normal)
        multiPeer.startMatching()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        multiPeer.stopMatching()
        multiPeer.disconnect()
    }
    
    //MARK: - Lazyload
    lazy var tableView: UITableView = {
        let tableView = UITableView()
        self.view.addSubview(tableView)
        tableView.snp.makeConstraints { (make) in
            make.bottom.equalTo(-kSafaArea.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(100)
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()
    
    lazy var fileBtn: UIButton = {
        let button = UIButton()
        self.view.addSubview(button)
        button.snp.makeConstraints { (make) in
            make.bottom.equalTo(self.tableView.snp_top).offset(-20)
            make.size.equalTo(CGSize(width: 180, height: 35))
            make.centerX.equalToSuperview()
        }
        button.setTitle("传输文件", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.addTarget(self, action: #selector(sendSourceData(_:)), for: .touchUpInside)
        return button
    }()
    
    lazy var videoBtn: UIButton = {
        let button = UIButton()
        self.view.addSubview(button)
        button.snp.makeConstraints { (make) in
            make.bottom.equalTo(self.fileBtn.snp_top).offset(-10)
            make.size.equalTo(CGSize(width: 180, height: 35))
            make.centerX.equalToSuperview()
        }
        button.setTitle("传输视频", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.addTarget(self, action: #selector(sendVideoData(_:)), for: .touchUpInside)
        return button
    }()
    
    lazy var dataBtn: UIButton = {
        let button = UIButton()
        self.view.addSubview(button)
        button.snp.makeConstraints { (make) in
            make.bottom.equalTo(self.videoBtn.snp_top).offset(-10)
            make.size.equalTo(CGSize(width: 180, height: 35))
            make.centerX.equalToSuperview()
        }
        button.setTitle("传输数据", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.addTarget(self, action: #selector(sendData(_:)), for: .touchUpInside)
        return button
    }()
    
    lazy var multiPeer: PKHMultiPeer = {
        let multiPeer = PKHMultiPeer(device: Device(deviceName: UIDevice.current.name),
                                     peerType: .browser,
                                     serviceType: "multipeer")
        multiPeer.delegate = self
        return multiPeer
    }()

}

extension BrowserVC {
    func settingCamera() {
        guard let index = AVCaptureDevice.devices(for: .video).firstIndex(where: {$0.position == .back}) else {
            return
        }
        
        let device = AVCaptureDevice.devices(for: .video)[index]
        deviceInput = try? AVCaptureDeviceInput(device: device)
        
        videoOutput = AVCaptureVideoDataOutput()
        let queue = dispatch_queue_serial_t(label: "videoQueue")
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as NSString as String : NSNumber(value: kCVPixelFormatType_32BGRA)]
        videoOutput?.setSampleBufferDelegate(self, queue: queue)
        
        captureSession = AVCaptureSession()
        if captureSession?.canAddInput(deviceInput!) == true {
            captureSession?.addInput(deviceInput!)
        }
        if captureSession?.canAddOutput(videoOutput!) == true {
            captureSession?.addOutput(videoOutput!)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        view.layer.addSublayer(previewLayer!)
        previewLayer?.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 400)
        previewLayer?.videoGravity = .resizeAspectFill
    }
    
    func startCaptureDate() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            dispatch_queue_serial_t(label: "serialQueue").async {
                
                if self.isStartVideo {
                    self.captureSession?.stopRunning()
                    if let device = self.connectDevice {
                        let success = self.multiPeer.stopStream(with: device)
                        if success {
                            print("流通道关闭成功")
                        }
                    }
                    self.isStartVideo = false
                }else {
                    self.captureSession?.startRunning()
                    if let device = self.connectDevice {
                        let success = self.multiPeer.startStream(to: device)
                        if success {
                            print("流通道开启成功")
                        }
                    }
                    self.isStartVideo = true
                }
            }
        }else {
            let alertVC = UIAlertController(title: nil, message: "请您设置允许APP访问您的相机->设置->隐私->相机", preferredStyle: .alert)
            let closeAction = UIAlertAction(title: "取消", style: .cancel) { _ in }
            alertVC.addAction(closeAction)
            present(alertVC, animated: true, completion: nil)
        }
    }
    
    @objc
    func sendSourceData(_ sender: UIButton) {
        if let device = connectDevice, let filePath = Bundle.main.path(forResource: "周杰伦 - 晴天.mp3", ofType: nil) {
            let progress = multiPeer.sendResource(with: filePath, device: device)
            progress?.addObserver(self, forKeyPath: "completedUnitCount", options: .new, context: nil)
        }
    }
    
    @objc
    func sendVideoData(_ sender: UIButton) {
        startCaptureDate()
    }
    
    @objc
    func sendData(_ sender: UIButton) {
        
    }
    
    func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }
        
        guard let quartzImage = context.makeImage() else { return nil }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let image = UIImage(cgImage: quartzImage)
        
        return image
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let progress = object as? Progress {
            print("传输进度: \(progress.fractionCompleted)")
            DispatchQueue.main.async {
                if progress.fractionCompleted > 0 {
                    self.fileBtn.setTitle("传输进度:\(progress.fractionCompleted)", for: .normal)
                }
            }
            
            if progress.fractionCompleted == 1.0 {
                progress.removeObserver(self, forKeyPath: "completedUnitCount", context: nil)
                DispatchQueue.main.async {
                    if progress.fractionCompleted > 0 {
                        self.fileBtn.setTitle("文件发送成功", for: .normal)
                    }
                }
            }
        }
    }
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
    func didDiscoverDevice(_ device: Device) {
        if let index = dataSource.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
            dataSource[index] = device
        }else {
            dataSource.append(device)
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func didLostDevice(_ device: Device) {
        if let index = dataSource.firstIndex(where: {$0.peerID.displayName == device.peerID.displayName}) {
            dataSource.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func connectStateDidChange(from device: Device, state: ConnectStatus) {
        print("设备状态信息改变: \(device), state: \(state)")
        if state == .connected {
            self.connectDevice = device
        }
    }
    
    func didDisconnect(with device: Device) {
        print("\(device.deviceName)断开连接")
        self.connectDevice = nil
    }
    
}

extension BrowserVC: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if videoOutput != nil {
            connection.videoOrientation = .portrait
            if let newImage = image(from: sampleBuffer),
               let data = UIImageJPEGRepresentation(newImage, 0.2),
               let device = connectDevice {
//                multiPeer.sendData(data, device: device)
                multiPeer.sendStream(with: data, device: device)
            }
        }
    }
}
