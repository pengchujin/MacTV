# 电视遥控器反向控制 Mac（试验功能）

本功能尚未进入 v0.1.1 下载包。源码构建后，在设置中开启「用电视遥控器控制 Mac」。默认关闭；不使用 ADB 或 Wi-Fi 作为运行时控制通道。

## 行为

- 接收电视地址 0 发给本机播放设备地址 4、8 或 11 的 CEC User Control Pressed / Released。
- 播放、暂停、停止、上一首、下一首交给 Mac 当前媒体播放器。播放与暂停分别发送，不使用同一个切换命令代替。
- 确认键映射是独立选项，默认关闭。部分 Mac 同时将电视确认键处理成 Return，可能操作前台 App；本功能不拦截这种系统行为。使用映射时请将播放器置于前台。
- 如果电视转发音量键，尝试调整当前 Mac 输出设备的软件音量或静音；不支持时明确提示。不会把收到的音量键再次发回电视。
- 通常电视遥控器音量键直接调整电视音量，电视不会把这些按键转发给 Mac。HDMI 输出通常也没有可写的软件音量。

## 实机验证（2026-09-17）

M4 Mac mini、macOS 27、REDMI MiTV-MFFU1。使用 ADB `input keyevent` 在电视端模拟按键，实际传输仍经过 HDMI-CEC。用户手持遥控器的确认键已在电视发送日志与 Mac 接收状态中观察到；其他品牌电视尚未验证。

| 验证 | 结果 |
| --- | --- |
| 电视暂停键 127 | 收到 `04:44:46`、`04:45`；QuickTime 从播放变为暂停 |
| 电视播放键 126 | 收到 `04:44:44`；QuickTime 从暂停恢复播放 |
| 电视确认键 23，开启映射 | 收到 `04:44:00`；QuickTime 切换为暂停 |
| 退出试验版后再发暂停 | QuickTime 继续播放，作为对照 |
| 电视音量减、加键 | 电视侧未记录对应发往 Mac 的 CEC 按键，因此未验证 Mac 音量调节 |
| 上一首、下一首、停止 | 解码与映射已实现，播放器实机效果待验证 |

测试使用本地静音 WAV，不修改播放器媒体库。现有正式版的签名、辅助功能权限保持不变。

## 实现与限制

- 只读轮询 DPCD RX 信息和缓冲区，不清除系统中断、不改逻辑地址，不申请电视或音响的身份。
- 以 RX 信息给出的长度读取，复读验证一致性；启动时丢弃旧缓冲区，拒绝发往其他设备、广播、非电视来源及不完整的按键。
- 相同缓冲区不会重复触发；需要可观察到的变化/松开才能识别下一次相同按键。轮询可能漏掉很短的按键，因此目前不保证长按连发。
- 发送/扫描期间暂停监听，切换连接后重新建立基线。接收通道和 macOS 共用，不能保证捕获每一个帧。
- 播放控制使用非公开 `MRMediaRemoteSendCommand`，兼容性随 macOS 和播放器变化。返回成功仅代表请求被接受，不代表播放器实际执行。

参考：[Linux DP CEC 接收实现](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/display/drm_dp_cec.c)、[AOSP HDMI-CEC 按键定义](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/hdmi/HdmiCecKeycode.java)、[MediaRemote 接口声明](https://github.com/theos/headers/blob/master/MediaRemote/MediaRemote.h)。

## 确认键映射与播放器复测

用户反馈 Apple Music 与网页播放无效时，电视确实发出了 `04:44:00`，Mac 设置显示「收到电视按键：确认」，但「确认键切换播放/暂停」关闭。开启该选项后，通过电视端 `input keyevent 23` 复测：

- Apple Music：当前曲目从播放切换为暂停，播放控件状态已核实。
- Safari 的 B 站播放器：视频暂停在 00:23，再次确认后恢复至 00:27。此结果仅覆盖该浏览器和测试页面，不代表所有网页播放器。

试验版恢复原有遥控器图标，移除临时 `TV → Mac` 菜单栏标题。
