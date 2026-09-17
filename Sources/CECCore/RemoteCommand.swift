import Foundation

public struct RemoteCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let group: String
    public let key: UInt8?
    public let opcode: UInt8?
    public let operands: [UInt8]
    public let reply: UInt8?
    public var isAudio: Bool { group == L("声音") }
    public init(_ id: String, _ title: String, _ symbol: String, _ group: String, key: UInt8? = nil, opcode: UInt8? = nil, operands: [UInt8] = [], reply: UInt8? = nil) {
        self.id=id; self.title=title; self.symbol=symbol; self.group=group; self.key=key; self.opcode=opcode; self.operands=operands; self.reply=reply
    }
    public static let all: [RemoteCommand] = [
        .init("wake",L("唤醒"),"power",L("电源"),key:0x6d),
        .init("standby",L("待机"),"moon",L("电源"),opcode:0x36),
        .init("powerToggle",L("切换电源"),"power.circle",L("电源"),key:0x6b),
        .init("viewOn",L("唤醒电视画面"),"tv",L("电源"),opcode:0x04),
        .init("up",L("向上"),"chevron.up",L("导航"),key:1),
        .init("down",L("向下"),"chevron.down",L("导航"),key:2),
        .init("left",L("向左"),"chevron.left",L("导航"),key:3),
        .init("right",L("向右"),"chevron.right",L("导航"),key:4),
        .init("select",L("确认"),"circle",L("导航"),key:0),
        .init("back",L("返回"),"chevron.backward",L("导航"),key:0x0d),
        .init("home",L("电视主页"),"house",L("导航"),key:9),
        .init("settings",L("设备设置"),"gearshape",L("导航"),key:0x0a),
        .init("contents",L("内容菜单"),"square.grid.2x2",L("导航"),key:0x0b),
        .init("context",L("上下文菜单"),"ellipsis.circle",L("导航"),key:0x11),
        .init("favorites",L("收藏菜单"),"star",L("导航"),key:0x0c),
        .init("info",L("节目信息"),"info.circle",L("导航"),key:0x35),
        .init("pageUp",L("上一页"),"arrow.up.doc",L("导航"),key:0x37),
        .init("pageDown",L("下一页"),"arrow.down.doc",L("导航"),key:0x38),
        .init("play",L("播放"),"play.fill",L("播放"),key:0x44),
        .init("pause",L("暂停"),"pause.fill",L("播放"),key:0x46),
        .init("stop",L("停止"),"stop.fill",L("播放"),key:0x45),
        .init("rewind",L("快退"),"backward.fill",L("播放"),key:0x48),
        .init("fastForward",L("快进"),"forward.fill",L("播放"),key:0x49),
        .init("previous",L("上一段"),"backward.end.fill",L("播放"),key:0x4c),
        .init("next",L("下一段"),"forward.end.fill",L("播放"),key:0x4b),
        .init("eject",L("弹出"),"eject.fill",L("播放"),key:0x4a),
        .init("subtitles",L("字幕"),"captions.bubble",L("播放"),key:0x51),
        .init("volumeDown",L("降低音量"),"minus",L("声音"),key:0x42),
        .init("volumeUp",L("升高音量"),"plus",L("声音"),key:0x41),
        .init("mute",L("静音 / 恢复"),"speaker.slash",L("声音"),key:0x43),
        .init("muteOn",L("设为静音"),"speaker.slash.fill",L("声音"),key:0x65),
        .init("muteOff",L("恢复声音"),"speaker.wave.2",L("声音"),key:0x66),
        .init("sound",L("切换音轨"),"waveform",L("声音"),key:0x33),
        .init("macInput",L("切回这台 Mac"),"desktopcomputer",L("输入与频道")),
        .init("macAddress",L("Mac 的连接位置"),"cable.connector",L("设备信息")),
        .init("audioOn",L("启用外置音响"),"hifispeaker.fill",L("声音")),
        .init("audioOff",L("关闭外置音响"),"hifispeaker",L("声音")),
        .init("input",L("输入源菜单"),"rectangle.on.rectangle",L("输入与频道"),key:0x34),
        .init("channelUp",L("下一频道"),"plus.rectangle",L("输入与频道"),key:0x30),
        .init("channelDown",L("上一频道"),"minus.rectangle",L("输入与频道"),key:0x31),
        .init("lastChannel",L("上次频道"),"arrow.uturn.backward",L("输入与频道"),key:0x32),
        .init("guide",L("节目指南"),"list.bullet.rectangle",L("输入与频道"),key:0x53),
        .init("record",L("录制"),"record.circle",L("录制"),key:0x47),
        .init("stopRecord",L("停止录制"),"stop.circle",L("录制"),key:0x4d),
        .init("pauseRecord",L("暂停录制"),"pause.circle",L("录制"),key:0x4e),
        .init("timerMenu",L("定时录制菜单"),"clock",L("录制"),key:0x54),
        .init("red",L("红色键"),"r.circle",L("彩色键"),key:0x72),
        .init("green",L("绿色键"),"g.circle",L("彩色键"),key:0x73),
        .init("yellow",L("黄色键"),"y.circle",L("彩色键"),key:0x74),
        .init("blue",L("蓝色键"),"b.circle",L("彩色键"),key:0x71),
        .init("powerStatus",L("电源状态"),"power",L("设备信息"),opcode:0x8f,reply:0x90),
        .init("name",L("设备名称"),"tag",L("设备信息"),opcode:0x46,reply:0x47),
        .init("physical",L("连接位置"),"point.3.connected.trianglepath.dotted",L("设备信息"),opcode:0x83,reply:0x84),
        .init("vendor",L("厂商编号"),"building.2",L("设备信息"),opcode:0x8c,reply:0x87),
        .init("version",L("CEC 版本"),"number",L("设备信息"),opcode:0x9f,reply:0x9e),
        .init("features",L("CEC 2.0 能力"),"checklist",L("设备信息"),opcode:0xa5,reply:0xa6),
        .init("audioStatus",L("音量与静音状态"),"speaker.wave.2",L("声音"),opcode:0x71,reply:0x7a),
        .init("systemAudioStatus",L("音响模式状态"),"hifispeaker",L("声音"),opcode:0x7d,reply:0x7e),
        .init("deckStatus",L("播放设备状态"),"play.rectangle",L("设备信息"),opcode:0x1a,operands:[3],reply:0x1b),
        .init("menuStatus",L("设备菜单状态"),"list.bullet",L("设备信息"),opcode:0x8d,operands:[2],reply:0x8e)
    ] + (1...4).map { .init("route\($0)","HDMI \($0)","rectangle.on.rectangle",L("输入与频道")) } + (0...9).map { .init("digit\($0)","\($0)","\($0).circle",L("数字键"),key:UInt8(0x20+$0)) } + [
        .init("enter",L("输入确认"),"return",L("数字键"),key:0x2b),
        .init("clear",L("清除输入"),"delete.left",L("数字键"),key:0x2c)
    ]
    public static var adjustmentMenu: RemoteCommand { find("settings")! }
    public static func find(_ id: String) -> RemoteCommand? { all.first { $0.id == id } }
}
public struct CECConnection: Codable, Identifiable, Sendable { public var id: UInt64; public var name: String }
public struct CECDevice: Codable, Identifiable, Sendable {
    public var address: UInt8
    public var name: String
    public var id: UInt8 { address }
    public init(address: UInt8, name: String) { self.address=address; self.name=name }
    public static func role(_ address: UInt8) -> String {
        switch address { case 0: return L("电视 / 显示器"); case 5: return L("音响"); case 4,8,11: return L("播放器"); case 1,2,9: return L("录像机"); case 3,6,7,10: return L("调谐器"); default: return L("CEC 设备") }
    }
}
public struct CECResponse: Codable, Sendable {
    public var message: String
    public var acknowledged: Bool
    public var raw: [UInt8]?
    public var devices: [CECDevice]?
    public var connections: [CECConnection]?
    public init(message:String, acknowledged:Bool = false, raw:[UInt8]? = nil, devices:[CECDevice]? = nil, connections:[CECConnection]? = nil) {
        self.message=message; self.acknowledged=acknowledged; self.raw=raw; self.devices=devices; self.connections=connections
    }
}

public enum EDIDAddress {
    public static func physical(_ bytes:[UInt8]) -> UInt16? {
        guard bytes.count >= 128,Array(bytes.prefix(8)) == [0,255,255,255,255,255,255,0], bytes.prefix(128).reduce(0, { ($0 + Int($1)) & 255 }) == 0 else { return nil }
        let count=min(Int(bytes[126]),bytes.count/128-1)
        guard count > 0 else { return nil }
        for block in 1...count {
            let data=Array(bytes[(block*128)..<((block+1)*128)])
            guard data[0] == 2,data.reduce(0, { ($0 + Int($1)) & 255 }) == 0 else { continue }
            let end=Int(data[2]);guard end >= 4,end <= 127 else { continue }
            var offset=4
            while offset < end {
                let length=Int(data[offset] & 31),tag=data[offset] >> 5
                guard offset+1+length <= end else { break }
                if tag == 3,length >= 5,Array(data[(offset+1)...(offset+3)]) == [3,12,0] {
                    let address=UInt16(data[offset+4]) << 8 | UInt16(data[offset+5])
                    return valid(address) ? address : nil
                }
                offset += length+1
            }
        }
        return nil
    }
    public static func valid(_ address:UInt16) -> Bool {
        guard address != 0,address != 0xffff else { return false }
        var zero=false
        for shift in [12,8,4,0] {
            let digit=(address >> shift) & 15
            if zero && digit != 0 { return false }
            if digit == 0 { zero=true }
        }
        return true
    }
}
