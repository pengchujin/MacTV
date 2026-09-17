# Xcode 构建与分发

打开 `ScreenRemote.xcodeproj`，为 App 和 ScreenVolumeCEC helper 选择自己的开发者团队。项目启用 Hardened Runtime，helper 通过 Xcode 的 Copy Files / Code Sign On Copy 嵌入。

```sh
xcodebuild -project ScreenRemote.xcodeproj -scheme ScreenRemote \
  -configuration Release -archivePath build/ScreenRemote.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates archive
```

也可在 Xcode 使用 Product → Archive。在 Organizer 选择归档，使用 Direct Distribution / Developer ID 分发并上传 Apple 公证。等待通过后导出最终 App。

**Apple Development 签名不等于 Developer ID 分发签名；成功上传不等于公证通过。** 发布前分别检查：

```sh
codesign --verify --deep --strict 'Screen Remote.app'
xcrun stapler validate 'Screen Remote.app'
spctl --assess --type execute --verbose=2 'Screen Remote.app'
ditto -c -k --keepParent 'Screen Remote.app' ScreenRemote-macOS-arm64.zip
shasum -a 256 ScreenRemote-macOS-arm64.zip
```

公证表示 Apple 完成安全检查，不是 Mac App Store 审核或电视兼容性认证。签名证书、私钥、账号凭据和本机导出配置不得提交到仓库。
