# Safe Location iOS 1.4

Safe Location 是面向 **iOS 27** 的本机定位模拟前端。界面由 SwiftUI + MapKit 实现，底层通过 Apple Developer DVT `LocationSimulation` 服务向 `locationd` 提供开发者模拟坐标。

它不使用旧的 WLOC / `gs-loc.apple.com` HTTPS MITM，因此不需要安装用于拦截 Apple 定位流量的自签根证书。

## 1.4 完整版功能

- iOS 27 **本机 Remote Pairing / Pair with Host**
- LocalDevVPN developer tunnel 检测与快捷打开
- 地图点选、地点搜索、经纬度输入
- Apple 地图 / Google 地图链接解析
- **剪贴板一键导入**：在地图 App 复制位置链接，回 Safe Location 点剪贴板图标
- **快捷指令分享入口**：Apple 地图分享 → Safe Location 快捷指令 → 导入或直接 Teleport
- 一键 Teleport / 移动到新位置 / 紧急恢复真实定位
- 收藏位置、最近位置
- **快捷城市卡片**
- **自定义位置方案**：保存坐标、移动方式、自动恢复时间
- **自动恢复倒计时**：15 / 30 / 60 / 120 / 240 分钟及 5–720 分钟自定义
- 道路路线规划与路线模拟
- GPX 导入与轨迹播放
- 虚拟摇杆实时移动
- DVT 会话健康检查、掉线自动重连、周期保活
- 前后台切换后的会话恢复
- 诊断页：RPPairing / LocalDevVPN / DVT 状态
- `safelocation://` URL Scheme，可供快捷指令调用
- iOS 26+ 使用 Apple 原生 **Liquid Glass** `glassEffect`；旧系统回退到 Material
- pairing 数据仅保存在 App 私有目录

> Safe Location 是开发者定位模拟工具，不是硬件 GNSS 伪装。第三方 App 可以通过系统接口或多信号交叉检查识别软件模拟位置。本项目不隐藏模拟标记，也不绕过第三方风控或反作弊。

## 首次使用

1. iPhone：**设置 → 隐私与安全性 → 开发者模式**，按提示重启并确认。
2. 侧载安装 `SafeLocation-unsigned.ipa`（SideStore / AltStore / Sideloadly 等会重新签名）。
3. 安装官方 **LocalDevVPN**。
4. Safe Location → **首次设置 → 开始本机配对**。
5. 切到 **设置 → 隐私与安全性 → 开发者模式 → Pair with Host**。
6. 输入 Safe Location 显示的 6 位配对码。
7. 打开并连接 LocalDevVPN。
8. 回到 Safe Location，地图选点或搜索地点，点击 **Teleport**。
9. 使用完后点击 **恢复真实**。

## Apple 地图位置导入

目前采用稳定的公开 API 路线，不使用 Share Extension 强行拉起主 App 的非公开技巧。

推荐流程：

1. Apple 地图打开地点。
2. 分享 / 复制链接。
3. 回到 Safe Location。
4. 点搜索框右侧 **剪贴板** 图标。
5. App 自动解析坐标或用 MapKit 搜索地点。
6. 确认后点击 Teleport。

如果链接本身带 `ll=` / `coordinate=` 等坐标参数，会直接解析；只有地点文字时，会通过 MapKit 搜索解析。

### 更接近“一键分享”的方式

1. 打开「快捷指令」App。
2. 新建一个接收共享 URL / 文本的快捷指令。
3. 添加 Safe Location 的 **导入地图位置** 或 **Teleport 到地图位置** 动作。
4. 把动作输入设成「快捷指令输入」，并开启「在共享表单中显示」。
5. 以后 Apple 地图 → 分享 → 这个快捷指令，即可把位置直接交给 Safe Location。

详细步骤见 `SHORTCUTS_SHARE_CN.md`。

## 自动恢复

主界面点击 **定时**，可以设置：

- 15 分钟
- 30 分钟
- 1 小时
- 2 小时
- 4 小时
- 自定义 5–720 分钟

如果当前尚未 Teleport，时间会作为“下一次 Teleport”的恢复规则；如果已经处于模拟定位，会立即开始倒计时。

倒计时依赖 App 的后台会话。系统强制结束 App、重启设备、DVT 会话先行中断时，系统行为可能先于倒计时发生；重新打开 Safe Location 后会再次检查截止时间。

## 位置方案

**方案** 页面包含快捷城市和自定义方案。

自定义方案可以保存：

- 名称
- 坐标
- 默认移动方式
- 自动恢复时间

选中方案后回到地图，点击 Teleport 即可应用。

## URL Scheme

可在快捷指令的“打开 URL”里调用：

```text
safelocation://select?lat=35.681236&lon=139.767125&name=Tokyo
safelocation://set?lat=35.681236&lon=139.767125&name=Tokyo
safelocation://set?input=35.681236,139.767125
safelocation://set?input=https%3A%2F%2Fmaps.apple.com%2F...&restore=30
safelocation://timer?minutes=30
safelocation://restore
safelocation://panic
safelocation://vpn
```

`select` 只选择位置；`set` 会尝试直接 Teleport，因此需要 RPPairing 和 LocalDevVPN 已正常。

## Windows 用户：无需 Mac 构建 IPA

项目自带 GitHub Actions：

1. GitHub 新建空仓库。
2. 上传本项目解压后的全部文件，必须包含 `.github`。
3. 打开仓库 **Actions**。
4. 选择 **Build Safe Location unsigned IPA**。
5. 点击 **Run workflow**。
6. 构建结束后下载 Artifact：`SafeLocation-unsigned-v1.4.0`。
7. 解压得到 `SafeLocation-unsigned.ipa`。
8. 用 SideStore / AltStore / Sideloadly 签名安装。

Workflow 会自动选择 GitHub Runner 上最新的 Xcode，以支持 iOS 26+ Liquid Glass API；构建脚本会从固定的 Locus commit 下载 `idevice` FFI，因此源码 ZIP 不需要携带约 95 MB 的静态库。

## 代码与安全设计

- RPPairing 保存于 Application Support 下的 App 私有目录，并设置 POSIX `0600`。
- 不上传坐标历史，不包含分析 SDK。
- 不安装 HTTPS MITM 根证书。
- LocalDevVPN 只用于建立本机 developer tunnel。
- 自动恢复、路线和摇杆不会尝试隐藏系统的软件模拟标记。
- 系统升级、重置设备或 pairing 数据损坏后可能需要重新 Pair with Host。

## 签名说明

Safe Location 无法绕过 Apple 的代码签名机制：

- 免费 Apple ID 侧载通常需要周期刷新。
- SideStore 可在手机上刷新签名，但仍属于开发签名刷新，不是永久签。
- 付费 Apple Developer 签名周期更长。

不要把 Apple ID 密码、`.p12` 私钥或 RPPairing 文件发给陌生人。

## 构建与质量检查

本地 macOS：

```bash
brew install xcodegen
./Scripts/quality_check.sh
./Scripts/build_unsigned_ipa.sh
```

Linux/Windows 可以执行源码结构和 Swift 语法检查，但最终 iOS 链接需要 Apple SDK，因此推荐使用仓库自带的 macOS GitHub Actions。

## 第三方组件

底层 DVT / Remote Pairing FFI 来自 Locus 项目固定 revision；许可证与说明见 `THIRD_PARTY_NOTICES.md`。
