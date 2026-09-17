import AppKit
import SwiftUI

struct TestRecord: Codable, Identifiable {
    var id=UUID(); var date=Date(); var connection:UInt64; var target:UInt8
    var command:String; var title:String; var result:String; var observation:String?; var deviceName:String?=nil
}
@MainActor final class RemoteController: ObservableObject {
    @Published var connections:[CECConnection]=[]
    @Published var devices:[CECDevice]=[]
    @Published var connection:UInt64=0
    @Published var target:UInt8=0 { didSet { UserDefaults.standard.set(Int(target),forKey:"target") } }
    @Published var audioTarget:UInt8=0 {
        didSet {
            UserDefaults.standard.set(Int(audioTarget),forKey:"audioTarget")
            if oldValue != audioTarget { volume=nil; muted=nil }
        }
    }
    @Published var manualAddressMode=false { didSet { normalizeTargets() } }
    @Published var busy=false
    @Published var scanning=false
    @Published var status=L("正在查找 HDMI 连接…")
    @Published var error=false
    @Published var page="remote"
    @Published var records:[TestRecord]=[]
    @Published var lastRecord:UUID?
    @Published var queryResults:[String:String]=[:]
    var ready:Bool { !scanning && connection != 0 && devices.contains { $0.address == target } }
    @Published var volume:Int?
    @Published var muted:Bool?
    private var pending:[(String,UInt8,String?)]=[]
    private let storage=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacCEC")
    init() {
        target=UInt8(clamping:UserDefaults.standard.integer(forKey:"target"))
        audioTarget=UInt8(clamping:UserDefaults.standard.integer(forKey:"audioTarget"))
        if let data=try? Data(contentsOf:storage.appendingPathComponent("tests.json")),let decoded=try? JSONDecoder().decode([TestRecord].self,from:data) { records=decoded }
    }
    func deviceName(_ address:UInt8) -> String { devices.first { $0.address == address }?.name ?? CECDevice.role(address) }
    func targetChoices(for selected:UInt8) -> [CECDevice] {
        var choices=devices
        if manualAddressMode,!devices.contains(where:{$0.address == selected}) {
            choices.append(CECDevice(address:selected,name:L("手动地址 %@（未发现）", String(selected))))
        }
        return choices
    }
    private func normalizeTargets() {
        guard !manualAddressMode else { return }
        if !devices.contains(where:{$0.address == target}) { target=devices.first?.address ?? 0 }
        if !devices.contains(where:{$0.address == audioTarget}) { audioTarget=devices.first(where:{$0.address == 5})?.address ?? devices.first?.address ?? 0 }
    }
    var selectedName:String { targetChoices(for:target).first(where:{$0.address == target})?.name ?? L("未发现设备") }
    var latest:TestRecord? { records.first { $0.id == lastRecord } }
    func call(_ args:[String],timeout:Double=14) async -> Result<CECResponse,Error> {
        guard let helper=Bundle.main.url(forAuxiliaryExecutable:"ScreenVolumeCEC")?.path else { return .failure(CECError.failure(L("内置控制组件缺失，请重新安装"))) }
        let result=await Task.detached(priority:.userInitiated) { CommandRunner.run(helper,arguments:args,timeout:timeout) }.value
        guard result.succeeded else { return .failure(CECError.failure(result.timedOut ? L("连接超时，请重新检测 HDMI 连接") : result.output.trimmingCharacters(in:.whitespacesAndNewlines))) }
        do { return .success(try JSONDecoder().decode(CECResponse.self,from:Data(result.output.utf8))) }
        catch { return .failure(CECError.failure(L("控制组件返回了无法识别的数据"))) }
    }
    func refresh() {
        guard !busy else { return }
        devices=[]; volume=nil; muted=nil; queryResults=[:]
        busy=true; scanning=true; error=false; status=L("正在查找 HDMI 连接…")
        Task {
            defer { busy=false; scanning=false; drain() }
            switch await call(["connections"]) {
            case .failure(let failure): status=failure.localizedDescription; error=true; connections=[]; devices=[]; connection=0
            case .success(let response):
                connections=response.connections ?? []
                if !connections.contains(where:{$0.id == connection}) { connection=connections.first?.id ?? 0 }
                guard connection != 0 else { devices=[]; status=L("没有可控制的 HDMI 连接。检查线缆、接口和设备的 CEC 设置。"); error=true; return }
                await scanCurrent()
            }
        }
    }
    func changeConnection(_ value:UInt64) {
        guard !busy else { return }
        connection=value; volume=nil; muted=nil; pending=[]; devices=[]; queryResults=[:]; lastRecord=nil
        busy=true; scanning=true
        Task { await scanCurrent(); busy=false; scanning=false; drain() }
    }
    private func scanCurrent() async {
        status=L("正在查找电视、播放器和音响…")
        switch await call(["discover",String(connection)],timeout:45) {
        case .success(let response): devices=response.devices ?? []; normalizeTargets(); status=devices.isEmpty ? L("未发现电视，请检查电视的 HDMI-CEC 设置") : L("已连接 · HDMI-CEC"); error=false
        case .failure(let failure): devices=[]; normalizeTargets(); status=failure.localizedDescription; error=true
        }
    }
    func perform(_ id:String, value:String?=nil) {
        guard !scanning, connection != 0 else { return }
        guard pending.count < 12 else { status=L("指令较多，请稍候"); return }
        let destination:UInt8=["audioOn","audioOff"].contains(id) ? 5 : (RemoteCommand.find(id)?.isAudio == true || id == "absoluteVolume") ? audioTarget : target
        guard manualAddressMode || devices.contains(where:{$0.address == destination}) else {
            status=L("没有发现目标设备，请重新检测连接"); error=true; return
        }
        pending.append((id,destination,value)); drain()
    }
    func performMediaKey(_ id:String) {
        // Bound repeat backlog, so releasing a key stops changes promptly.
        guard pending.count < 2 else { return }
        perform(id)
    }
    private func drain() {
        guard !busy,!pending.isEmpty else { return }
        let (id,destination,value)=pending.removeFirst()
        let bus=connection
        let title=RemoteCommand.find(id)?.title ?? L("设置音量")
        busy=true; error=false; status=L("正在发送“%@”…", String(title))
        Task {
            var args=[id,String(bus),String(destination)]
            if let value { args.append(value) }
            let response=await call(args)
            switch response {
            case .success(let value):
                status=value.message; error=false
                if id == "audioStatus", bus == connection, destination == audioTarget, let raw=value.raw, raw.count == 3 {
                    let level=Int(raw[2] & 127); volume=level <= 100 ? level : nil; muted=raw[2] & 128 != 0
                } else if ["volumeUp","volumeDown","mute"].contains(id) { volume=nil; muted=nil }
                if value.raw != nil || id == "macAddress" { queryResults["\(bus).\(destination).\(id)"]="\(deviceName(destination)) · \(Date().formatted(date:.omitted,time:.shortened))\n\(value.message)" }
                let record=TestRecord(connection:bus,target:destination,command:id,title:title,result:value.message + (value.acknowledged ? L(" · 观察到发送确认") : L(" · 未观察到发送确认")),deviceName:deviceName(destination))
                records.insert(record,at:0); lastRecord=record.id
            case .failure(let failure):
                status=failure.localizedDescription; error=true; pending=[]
                if id == "audioStatus" { volume=nil; muted=nil }
                let record=TestRecord(connection:bus,target:destination,command:id,title:title,result:failure.localizedDescription,deviceName:deviceName(destination))
                records.insert(record,at:0); lastRecord=record.id
            }
            if records.count > 500 { records=Array(records.prefix(500)) }
            save(); busy=false; drain()
        }
    }
    func mark(_ observation:String) {
        guard let id=lastRecord,let index=records.firstIndex(where:{$0.id == id}) else { return }
        records[index].observation=observation; save()
    }
    private func save() {
        try? FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true)
        if let data=try? JSONEncoder().encode(records) { try? data.write(to:storage.appendingPathComponent("tests.json"),options:.atomic) }
    }
    func copyReport() {
        let content=L("屏幕遥控 0.1 · %@\n%@\n", Date().formatted(), String(ProcessInfo.processInfo.operatingSystemVersionString)) + records.map {
            L("%@ | HDMI %@ | %@（目标 %@） | %@ | %@ | 实测：%@", String($0.date.formatted()), String($0.connection), String($0.deviceName ?? L("设备")), String($0.target), String($0.title), String($0.result), String($0.observation ?? L("未标记")))
        }.joined(separator:"\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content,forType:.string)
        status=L("测试报告已复制"); error=false
    }
}
