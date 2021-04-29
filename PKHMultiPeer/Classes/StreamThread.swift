//
//  StreamThread.swift
//  PKHMultiPeer
//
//  Created by Pan on 2021/4/28.
//

import Foundation

class StreamThread: NSObject {
    
    private var thread: Thread?
        
    deinit {
        print("\(Self.self) deinit")
        stop()
    }
    
    func executeTask(_ block: @escaping (@convention(block) ()->())) {
        if let thread = self.thread {
            perform(#selector(__executeTask(_:)), on: thread, with: block, waitUntilDone: false)
        }else {
            self.thread = Thread(block: {
                var context = CFRunLoopSourceContext()
                let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 100, false)
            })
            self.thread?.start()
            perform(#selector(__executeTask(_:)), on: self.thread!, with: block, waitUntilDone: false)
        }
    }
    
    func stop() {
        guard let thread = self.thread else {
            return
        }
        perform(#selector(__stop), on: thread, with: nil, waitUntilDone: true)
    }
    
    //MARK: - Private Method
    @objc private func __executeTask(_ block: @escaping (@convention(block) ()->())) {
        block()
    }
    
    @objc private func __stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
        self.thread = nil
    }
    
}
