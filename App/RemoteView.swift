import AppKit
import SwiftUI

struct RemoteKey: View {
    let title: String
    let symbol: String
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.borderless).clipShape(Circle())
        .accessibilityLabel(title).help(title)
    }
}

struct RemoteView: View {
    @ObservedObject var model: RemoteController
    @ObservedObject var volumeKeys: SystemVolumeBridge
    var openSettings: () -> Void
    @AppStorage("largeText") var largeText = false
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    private var secondary: Color { contrast == .increased ? .primary : .secondary }
    private func key(_ id: String, size: CGFloat = 44) -> some View {
        let command = RemoteCommand.find(id)!
        return RemoteKey(title: command.title, symbol: command.symbol, size: size) { model.perform(id) }
            .disabled(!model.ready)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            if model.devices.isEmpty { empty.padding(.vertical, 26) }
            else {
                VStack(spacing: 18) {
                    directionPad.padding(.top, 6)
                    HStack(spacing: 12) {
                        labeledKey("back", title: L("返回"))
                        labeledKey(RemoteCommand.adjustmentMenu.id, title: L("菜单"))
                        Button { InputMenuActions.show(model: model) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: "rectangle.on.rectangle").font(.system(size: 19))
                                Text(L("输入源")).font(.system(size: largeText ? 16 : 12))
                            }.frame(width: 74, height: 62)
                        }.buttonStyle(.borderless).disabled(!model.ready).accessibilityLabel(L("切换输入源"))
                    }
                    volume
                }
            }
            feedback.padding(.top, 16).padding(.bottom, 12)
            Divider()
            HStack {
                Button(action: openSettings) {
                    Label(volumeKeys.needsPermission ? L("启用键盘音量键") : L("设置"), systemImage: volumeKeys.needsPermission ? "keyboard" : "gearshape")
                        .frame(minHeight: 30)
                }.buttonStyle(.borderless)
                Spacer()
                if model.busy { ProgressView().controlSize(.mini).accessibilityLabel(L("正在通信")) }
                Menu {
                    Button(L("电视主页")) { model.perform("home") }.disabled(!model.ready)
                    Button(L("重新检测电视")) { model.refresh() }.disabled(model.busy)
                    Button(L("查询实际音量")) { model.perform("audioStatus") }.disabled(!model.ready)
                    Button(L("设置…"), action: openSettings).keyboardShortcut(",")
                    Divider()
                    Button(L("退出 MacTV")) { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 30)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L("更多操作"))
            }.font(.system(size: largeText ? 16 : 12)).foregroundStyle(secondary)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 10)
        .frame(width: largeText ? 372 : 320)
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : .clear)
        .tint(.primary)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv").font(.system(size: 22, weight: .regular)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if model.devices.count > 1 {
                    Menu {
                        ForEach(model.devices) { device in
                            Button(device.name) { model.target = device.address }
                        }
                    } label: { Text(model.selectedName).font(.system(size: largeText ? 21 : 16, weight: .semibold)) }
                    .menuStyle(.borderlessButton).disabled(model.busy)
                } else {
                    Text(model.devices.isEmpty ? L("MacTV") : model.selectedName)
                        .font(.system(size: largeText ? 21 : 16, weight: .semibold)).lineLimit(1)
                }
                Text(model.scanning ? L("正在寻找电视…") : model.devices.isEmpty ? L("让电视更好用作 Mac 显示器") : L("HDMI · 已连接"))
                    .font(.system(size: largeText ? 16 : 12)).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button(L("唤醒电视")) { model.perform("wake") }
                Button(L("电视待机")) { model.perform("standby") }
                Divider()
                Button(L("查询电源状态")) { model.perform("powerStatus") }
            } label: {
                Image(systemName: "power").font(.system(size: 19)).frame(width: 36, height: 36)
                    .background(.primary.opacity(0.06), in: Circle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(!model.ready).accessibilityLabel(L("电视电源"))
        }.padding(.bottom, 20)
    }
    private var directionPad: some View {
        ZStack {
            Circle().fill(.primary.opacity(0.055))
            Circle().strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.08), lineWidth: 1)
            VStack(spacing: 4) {
                key("up")
                HStack(spacing: 4) {
                    key("left")
                    Button { model.perform("select") } label: {
                        Text("OK").font(.system(size: 17, weight: .semibold)).frame(width: 62, height: 62)
                            .background(.primary.opacity(0.055), in: Circle())
                    }.buttonStyle(.borderless).disabled(!model.ready)
                        .accessibilityLabel(L("确认")).help(L("确认 · Return"))
                    key("right")
                }
                key("down")
            }
        }.frame(width: 192, height: 192)
    }
    private func labeledKey(_ id: String, title: String) -> some View {
        let command = RemoteCommand.find(id)!
        return Button { model.perform(id) } label: {
            VStack(spacing: 7) {
                Image(systemName: command.symbol).font(.system(size: 19))
                Text(title).font(.system(size: largeText ? 16 : 12))
            }.frame(width: 74, height: 62).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.borderless).disabled(!model.ready).help(command.title)
    }
    private var volume: some View {
        HStack(spacing: 6) {
            key("mute")
            HStack(spacing: 0) {
                key("volumeDown", size: 50)
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 16))
                    Text(model.volume.map { "\($0)%" } ?? L("音量"))
                        .font(.system(size: largeText ? 16 : 12)).monospacedDigit()
                }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                key("volumeUp", size: 50)
            }.padding(.horizontal, 4).frame(height: 60)
                .background(.primary.opacity(0.055), in: Capsule())
        }
    }
    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: model.scanning ? "antenna.radiowaves.left.and.right" : "tv.and.mediabox")
                .font(.system(size: 40, weight: .regular)).foregroundStyle(secondary)
            Text(model.scanning ? L("正在检测 HDMI-CEC") : L("连接你的电视")).font(.headline)
            Text(L("通过支持 CEC 的 HDMI 接口连接，\n并在电视设置中开启 HDMI-CEC。"))
                .font(.system(size: largeText ? 18 : 13)).foregroundStyle(secondary).multilineTextAlignment(.center)
            Button(L("重新检测")) { model.refresh() }.disabled(model.busy)
        }
    }
    private var feedback: some View {
        HStack(alignment: .top, spacing: 6) {
            if model.error { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
            Text(model.status).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: largeText ? 16 : 12)).foregroundStyle(secondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
            .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @ObservedObject var model: RemoteController
    @ObservedObject var volumeKeys: SystemVolumeBridge
    @AppStorage("largeText") var largeText = false
    var body: some View {
        Form {
            Section(L("电视与音响")) {
                Picker(L("HDMI 连接"), selection: Binding(get: { model.connection }, set: { model.changeConnection($0) })) {
                    if model.connections.isEmpty { Text(L("未连接")).tag(UInt64(0)) }
                    ForEach(model.connections) { Text($0.name).tag($0.id) }
                }.disabled(model.busy)
                Picker(L("音量控制"), selection: $model.audioTarget) {
                    if model.devices.isEmpty { Text(L("未发现设备")).tag(UInt8(0)) }
                    ForEach(model.devices) { Text($0.name).tag($0.address) }
                }.disabled(model.busy)
                Button(L("重新检测设备")) { model.refresh() }.disabled(model.busy)
            }
            Section(L("键盘")) {
                Toggle(L("用 Mac 音量键控制电视"), isOn: $volumeKeys.enabled)
                Text(volumeKeys.status).foregroundStyle(.secondary)
                if volumeKeys.needsPermission {
                    Button(L("允许辅助功能…")) { volumeKeys.requestPermission() }
                }
                Text(L("仅在声音输出到 HDMI 时接管音量键。切换到耳机或内置扬声器后，音量键恢复系统控制。Option + 音量键仍打开系统声音设置。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("外观与操作")) {
                Toggle(L("使用大字号"), isOn: $largeText)
                Text(L("遥控器打开时：方向键移动，Return 确认，Delete 返回。外观跟随系统。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("连接诊断")) {
                Text(model.status).textSelection(.enabled)
                HStack {
                    Button(L("电源状态")) { model.perform("powerStatus") }
                    Button(L("CEC 版本")) { model.perform("version") }
                    Button(L("实际音量")) { model.perform("audioStatus") }
                }.disabled(!model.ready)
                DisclosureGroup(L("最近的通信记录")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.records.prefix(6)) { record in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).fontWeight(.medium)
                                Text(record.result).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        Button(L("复制诊断报告")) { model.copyReport() }
                    }.padding(.vertical, 8)
                }
                Text(L("功能取决于电视支持情况。发送完成不代表电视已执行；没有音量反馈时，只提供音量加减。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).font(.system(size: largeText ? 17 : 13)).frame(minWidth: 480, minHeight: 580)
    }
}

@MainActor private final class InputMenuActions: NSObject {
    let model: RemoteController
    init(model: RemoteController) { self.model = model }
    @objc func perform(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { model.perform(id) }
    }
    static func show(model: RemoteController) {
        let handler = InputMenuActions(model: model)
        let menu = NSMenu()
        func add(_ title: String, command: String, to parent: NSMenu) {
            let item = NSMenuItem(title: title, action: #selector(perform(_:)), keyEquivalent: "")
            item.target = handler; item.representedObject = command; parent.addItem(item)
        }
        add(L("打开电视输入源菜单"), command: "input", to: menu)
        add(L("切回这台 Mac"), command: "macInput", to: menu)
        menu.addItem(.separator())
        for port in 1...4 {
            add("HDMI \(port)", command: "route\(port)", to: menu)
            menu.items.last?.toolTip = L("通过 HDMI-CEC 请求切换；实际支持取决于电视")
        }
        _ = withExtendedLifetime(handler) { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }
}
