import AppKit
import ApplicationServices
import CoreAudio
import SwiftUI

@MainActor final class SystemVolumeBridge:ObservableObject {
    @Published var enabled:Bool { didSet { UserDefaults.standard.set(enabled,forKey:"systemVolumeKeys"); update() } }
    @Published var status=L("正在检查音量键权限…")
    @Published var needsPermission=false
    @Published var lastKey=L("尚未收到音量键")
    private var tap:CFMachPort?
    private var source:CFRunLoopSource?
    private var timer:Timer?
    private var hdmiOutput=false
    private var held=Set<Int>()
    private var lastSent=0.0
    private let ready:()->Bool
    private let action:(String)->Void
    init(ready:@escaping ()->Bool,action:@escaping (String)->Void, monitoring:Bool = true) {
        self.ready=ready;self.action=action
        enabled=UserDefaults.standard.object(forKey:"systemVolumeKeys") == nil ? true : UserDefaults.standard.bool(forKey:"systemVolumeKeys")
        guard monitoring else { return }
        update()
        timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }
    private func isHDMIOutput() -> Bool {
        var property=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&property,0,nil,&size,&device) == noErr else { return false }
        property.mSelector=kAudioDevicePropertyTransportType
        var transport:UInt32=0;size=4
        guard AudioObjectGetPropertyData(device,&property,0,nil,&size,&transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
    }
    func update() {
        hdmiOutput=isHDMIOutput()
        needsPermission=enabled && !AXIsProcessTrusted()
        if !enabled { stop();status=L("音量键接管已关闭");return }
        if needsPermission { stop();status=L("需要允许“MacTV”使用辅助功能");return }
        if tap == nil { start() }
        guard tap != nil else { status=L("音量键监听未启动，请重新打开 App");return }
        status = !hdmiOutput ? L("当前不是 HDMI 输出，音量键交给 macOS") : !ready() ? L("等待可用的 HDMI 显示器") : L("已接管 HDMI 输出的音量键和静音键")
    }
    func requestPermission() {
        _=AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    private func start() {
        let callback:CGEventTapCallBack = { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<SystemVolumeBridge>.fromOpaque(context).takeUnretainedValue().handle(type:type,event:event)
            }
        }
        // Only system-defined media-key events, never ordinary typed text.
        guard let port=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:CGEventMask(1) << 14,callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap=port;source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,port,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        CGEvent.tapEnable(tap:port,enable:true)
    }
    private func stop() {
        if let tap { CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        source=nil;tap=nil;held.removeAll()
    }
    private func handle(type:CGEventType,event:CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap,enabled { CGEvent.tapEnable(tap:tap,enable:true) }
            held.removeAll();return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14,let native=NSEvent(cgEvent:event),let key=VolumeKey.decode(subtype:Int(native.subtype.rawValue),data:native.data1) else { return Unmanaged.passUnretained(event) }
        if !key.down {
            return held.remove(key.code) != nil ? nil : Unmanaged.passUnretained(event)
        }
        // Refresh at the key press so switching to headphones never changes a display.
        guard enabled,isHDMIOutput(),ready() else { return Unmanaged.passUnretained(event) }
        // Preserve Option-volume's native sound-settings shortcut.
        guard event.flags.intersection([.maskAlternate,.maskCommand,.maskControl]).isEmpty else { return Unmanaged.passUnretained(event) }
        let wasHeld=held.contains(key.code);held.insert(key.code)
        if key.code == 7 && (wasHeld || key.repeating) { return nil }
        let now=ProcessInfo.processInfo.systemUptime
        if key.code != 7 && now-lastSent < 0.10 { return nil }
        lastSent=now
        lastKey=L("收到：") + (key.code == 0 ? L("音量加") : key.code == 1 ? L("音量减") : L("静音")) + " · " + Date().formatted(date:.omitted,time:.standard)
        action(key.command)
        return nil
    }
}
