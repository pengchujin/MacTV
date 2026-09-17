import Foundation
/// NX_SYSDEFINED / NX_SUBTYPE_AUX_CONTROL_BUTTONS payload. Ignore unrelated media keys.
public struct VolumeKey: Equatable {
    public let code:Int
    public let down:Bool
    public let repeating:Bool
    public var command:String { code == 0 ? "volumeUp" : code == 1 ? "volumeDown" : "mute" }
    public static func decode(subtype:Int,data:Int) -> VolumeKey? {
        guard subtype == 8 else { return nil }
        let code=(data >> 16) & 0xffff,state=(data >> 8) & 0xff
        guard [0,1,7].contains(code),[0x0a,0x0b].contains(state) else { return nil }
        return VolumeKey(code:code,down:state == 0x0a,repeating:data & 1 != 0)
    }
}
