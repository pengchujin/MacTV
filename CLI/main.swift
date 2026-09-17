import Foundation
import Darwin
let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("screenvolume-cec.lock").path
let fd = open(lockPath,O_CREAT | O_RDWR,0o600)
guard fd >= 0, flock(fd,LOCK_EX | LOCK_NB) == 0 else { fputs(L("CEC 控制正在执行，请稍后重试\n"),stderr); exit(1) }
defer { flock(fd,LOCK_UN); close(fd) }
func emit(_ response: CECResponse) throws { print(String(data:try JSONEncoder().encode(response),encoding:.utf8)!) }
func describe(_ frame: [UInt8]) -> String {
    guard frame.count >= 3 else { return L("已收到设备回复") }
    switch frame[1] {
    case 0x47: return L("设备名称：") + (String(bytes:frame.dropFirst(2),encoding:.ascii) ?? L("未知"))
    case 0x90: return L("电源：") + ([0:L("已开启"),1:L("待机"),2:L("正在开启"),3:L("正在待机")][frame[2]] ?? L("未知状态"))
    case 0x7a:
        let volume=frame[2] & 127
        return L("音量：") + (volume <= 100 ? "\(volume)%" : L("设备未提供数值")) + (frame[2] & 128 != 0 ? L(" · 已静音") : L(" · 未静音"))
    case 0x7e: return L("外置音响模式：") + (frame[2] == 1 ? L("开启") : frame[2] == 0 ? L("关闭") : L("未知"))
    case 0x9e: return L("CEC 版本：") + ([4:"1.3a",5:"1.4",6:"2.0"][frame[2]] ?? L("编号 %@", String(frame[2])))
    case 0x84 where frame.count >= 5: return String(format:L("连接位置：%X.%X.%X.%X"),frame[2] >> 4,frame[2] & 15,frame[3] >> 4,frame[3] & 15)
    case 0x87 where frame.count >= 5: return String(format:L("厂商编号：%02X%02X%02X"),frame[2],frame[3],frame[4])
    default: return L("设备回复：") + frame.map{ String(format:"%02X",$0) }.joined(separator:" ")
    }
}
do {
    let args=Array(CommandLine.arguments.dropFirst())
    let action=args.first ?? "connections"
    if action == "connections" {
        let connections=try NativeCEC.connections()
        try emit(.init(message:connections.isEmpty ? L("未找到可用的 CEC 连接") : L("找到 %@ 个 HDMI 连接", String(connections.count)),connections:connections))
    } else {
        let connectionID=args.count > 1 ? UInt64(args[1]) : nil
        if args.count > 1,connectionID == nil { throw CECError.failure(L("无效的 HDMI 连接编号")) }
        let target=args.count > 2 ? UInt8(args[2]) : 0
        guard let target, target < 15 else { throw CECError.failure(L("无效的目标地址")) }
        let session=CECSession(io:try NativeCEC(connectionID:connectionID))
        if action == "discover" {
            let devices=try session.discover()
            try emit(.init(message:devices.isEmpty ? L("暂未收到设备回应，可手动选择目标后测试") : L("发现 %@ 台设备", String(devices.count)),devices:devices))
        } else if action == "macInput" || action == "macAddress" || action == "audioOn" {
            let address=try NativeCEC.macPhysicalAddress(connectionID:connectionID)
            if action == "macInput" {
                try session.activateMac(physical:address)
                try emit(.init(message:L("已请求电视切回这台 Mac"),acknowledged:session.acknowledged))
            } else if action == "audioOn" {
                guard target == 5 else { throw CECError.failure(L("外置音响控制应发给音响地址 5")) }
                try session.command([0x70,UInt8(address >> 8),UInt8(address & 255)],to:5)
                try emit(.init(message:L("已请求启用外置音响"),acknowledged:session.acknowledged))
            } else {
                try emit(.init(message:String(format:L("Mac 连接位置：%X.%X.%X.%X"),address >> 12,(address >> 8) & 15,(address >> 4) & 15,address & 15)))
            }
        } else if action == "audioOff" {
            guard target == 5 else { throw CECError.failure(L("外置音响控制应发给音响地址 5")) }
            try session.command([0x70],to:5)
            try emit(.init(message:L("已请求关闭外置音响模式"),acknowledged:session.acknowledged))
        } else if action.hasPrefix("route"), let port = Int(action.dropFirst(5)), (1...4).contains(port) {
            try session.route(to: UInt16(port) << 12)
            try emit(.init(message:L("已请求切换到 HDMI %@", String(port)),acknowledged:session.acknowledged))
        } else if action == "absoluteVolume" {
            guard args.count == 4, let volume=UInt8(args[3]),volume <= 100 else { throw CECError.failure(L("音量应在 0–100 之间")) }
            try session.command([0x73,volume],to:target)
            try emit(.init(message:L("已发送音量 %@%；需要 CEC 2.0 支持", String(volume)),acknowledged:session.acknowledged))
        } else if action == "probe" {
            try emit(.init(message:try session.probe()))
        } else if let command=RemoteCommand.find(action) {
            if let key=command.key {
                try session.sendKey(key,to:target)
                try emit(.init(message:L("已发送“%@”", String(command.title)),acknowledged:session.acknowledged))
            } else if let opcode=command.opcode {
                if let reply=command.reply {
                    let frame=try session.query([opcode]+command.operands,to:target,reply:reply)
                    try emit(.init(message:describe(frame),acknowledged:session.acknowledged,raw:frame))
                } else {
                    try session.command([opcode]+command.operands,to:target)
                    try emit(.init(message:L("已发送“%@”", String(command.title)),acknowledged:session.acknowledged))
                }
            }
        } else { throw CECError.failure(L("未知操作")) }
    }
} catch { fputs(error.localizedDescription + "\n",stderr); exit(1) }
