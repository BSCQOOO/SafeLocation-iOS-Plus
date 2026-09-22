# Safe Location 1.1.0 构建说明（Windows 用户）

## 最省事：GitHub Actions 云构建

1. 解压源码包。
2. GitHub 新建一个空仓库。
3. 上传解压后的所有文件，包括隐藏目录 `.github`。
4. 打开仓库的 **Actions**。
5. 点击 **Build Safe Location unsigned IPA**。
6. 点击 **Run workflow**。
7. 等待 macOS Runner 完成。
8. 下载 Artifact：`SafeLocation-unsigned-v1.1.0`。
9. 解压后得到 `SafeLocation-unsigned.ipa`。
10. 用 SideStore / AltStore / Sideloadly 按你自己的签名方式安装。

## 为什么 1.1 要选最新 Xcode

1.1 在 iOS 26+ 使用 SwiftUI 原生 Liquid Glass `glassEffect`。Workflow 会自动从 GitHub Runner 已安装的 Xcode 中选择最新版本，然后再构建。

## 构建前自动完成的步骤

`Scripts/build_unsigned_ipa.sh` 会：

1. 下载固定 Locus commit 中的 `idevice` FFI。
2. 使用 XcodeGen 生成 Xcode 工程。
3. 使用 iPhoneOS SDK 进行无签名构建。
4. 打包 `Payload/Safe Location.app`。
5. 输出 `SafeLocation-unsigned.ipa`。

## 注意

- unsigned IPA 仍然需要 SideStore / AltStore / Sideloadly 等重新签名。
- 不要把 Apple ID 密码、`.p12` 私钥或 RPPairing 文件上传到公开仓库。
- 如果 GitHub Runner 的最新 Xcode 暂时不可用，可在 Actions 日志中查看 `xcodebuild -version` 后再决定是否回退到 1.0 的 Material UI。
