# Xcode 构建与分发

打开 `MacTV.xcodeproj`，为 App 和 MacTVCEC helper 选择自己的开发者团队。项目启用 Hardened Runtime，helper 通过 Xcode 的 Copy Files / Code Sign On Copy 嵌入。

```sh
xcodebuild -project MacTV.xcodeproj -scheme MacTV \
  -configuration Release -archivePath build/MacTV.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates archive
```

也可在 Xcode 使用 Product → Archive。在 Organizer 选择归档，使用 Direct Distribution / Developer ID 分发并上传 Apple 公证。等待通过后导出最终 App。

**Apple Development 签名不等于 Developer ID 分发签名；成功上传不等于公证通过。** 发布前分别检查：

```sh
codesign --verify --deep --strict 'MacTV.app'
xcrun stapler validate 'MacTV.app'
spctl --assess --type execute --verbose=2 'MacTV.app'
ditto -c -k --keepParent 'MacTV.app' MacTV-macOS-arm64.zip
shasum -a 256 MacTV-macOS-arm64.zip
```

公证表示 Apple 完成安全检查，不是 Mac App Store 审核或电视兼容性认证。签名证书、私钥、账号凭据和本机导出配置不得提交到仓库。

## 同步下载入口与 Homebrew

发布新版本后，更新 README 下载按钮中的版本和 ZIP 文件名，使按钮始终直达安装包。

在 [pengchujin/homebrew-tap](https://github.com/pengchujin/homebrew-tap) 更新 `Casks/mactv.rb` 的 `version` 和 `sha256`。使用公开 Release 下载文件计算校验值，然后验证：

```sh
brew audit --cask pengchujin/tap/mactv
brew fetch --cask pengchujin/tap/mactv
brew install --cask pengchujin/tap/mactv
```

若本机已手动安装完全相同的 App，可加 `--adopt` 交由 Homebrew 管理；不要用 `--force` 覆盖未知版本。
