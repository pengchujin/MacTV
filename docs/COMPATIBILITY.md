# 设备兼容性

需要 Apple Silicon Mac 和支持 CEC 的电视、线缆及连接路径。App 最低 macOS 14；Apple 指定 USB-C 转换器的 CEC 支持要求 macOS 14.4+。

Apple 官方内置 HDMI CEC 名单包括 M4/M4 Pro Mac mini、2025 M4 Max/M3 Ultra Mac Studio，以及指定 M3 Pro/Max、M4 系列、M5 Pro/Max MacBook Pro。请以 [Apple 最新名单](https://support.apple.com/zh-cn/108928)为准，不要仅凭 HDMI 接口版本判断。

## 已验证与待适配

当前实机：M4 Mac mini + REDMI MiTV-MFFU1。

| 功能 | 当前证据 |
| --- | --- |
| 方向、确认、返回 | 用户实测可用 |
| 切回 Mac | 从 HDMI1 回切到 Mac 所在 HDMI2 已验证 |
| 设备设置菜单 | 打开 Android 系统设置，不是 REDMI 快捷调整面板 |
| 输入源菜单、其他 HDMI 端口 | 尚未验证成功 |
| 音量数值回读 | 本机拒绝对应查询；App 不显示虚构百分比 |
| 其他品牌 | 尚未用本 App 实机验证 |

CEC 支持不代表全部功能都实现。LG SIMPLINK、Samsung Anynet+、Sony BRAVIA Sync 等以 CEC 为基础，但功能方向、响应和时序不同。品牌和型号适配仍在计划中。

## 反馈

请在 Issue 中提供 Mac 型号、macOS 版本、电视型号和固件、连接方式，以及具体哪个按钮有效或无效。可从 App 设置复制诊断报告，分享前移除不希望公开的设备名称或其他私人信息。

不需要提供 Apple 账号、证书、ADB 地址或网络密码。
