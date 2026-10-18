import AppKit
import ApplicationServices

final class MediaKeys {
    var onKey: ((Int) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    func start(requestPermission: Bool) -> Bool {
        stop()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: requestPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let mask = CGEventMask(1) << 14
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap,place: .headInsertEventTap,options: .defaultTap,eventsOfInterest: mask,callback: { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap = owner.tap { CGEvent.tapEnable(tap: tap,enable: true) }; return Unmanaged.passUnretained(event) }
            guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let key = (ns.data1 & 0xFFFF0000) >> 16, state = (ns.data1 & 0xFF00) >> 8
            guard [0,1,7].contains(key) else { return Unmanaged.passUnretained(event) }
            if state == 0xA { DispatchQueue.main.async { owner.onKey?(key) } }
            return nil
        },userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes) }
        CGEvent.tapEnable(tap: tap,enable: true); return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap,enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        source = nil; tap = nil
    }
    deinit { stop() }
}
