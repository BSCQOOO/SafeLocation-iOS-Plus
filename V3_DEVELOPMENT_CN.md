# SafeLocation 3.0 alpha：自维护版开发记录

基于已通过 R39 构建的通用隧道分支。保留原有地图界面、Bundle ID、配对和定位功能；新功能只在设置中的签名与应用管理页面。版本号 3.0.0 / Build 24 为内部技术验证包，不代表正式发布。

## 本轮实际功能
- 读取本机嵌入描述文件 CMS 中的 plist，显示到期日期和剩余时间；不是 CMS 验签，不判断证书吊销。
- 用户主动授权后安排到期提醒，重新启动时根据实际描述文件调整通知；不自动续签。
- 基于原有固定 idevice FFI，通过 RPPairing 建立 RSD，分别尝试 AFC、InstallationProxy 连接。仅连接，不发送安装命令、不读取应用列表，不写坐标。需先结束定位，保留本机配对文件。当前仍用 49152，动态服务发现另行研究。
- IPA 私有暂存、流式 SHA-256、大小限制、去重、删除；ZIP 魔数检查不代表完整 IPA 验证。
- 查询本仓库 GitHub Releases 最新正式版本与资源，不自动下载、安装或更新。
- 新增合成数据回归检查、自动构建。未上传真实配对、账号或签名私钥。

## 最关键的真机验收
1. 使用同一 Apple Account 和 Bundle ID 覆盖安装测试包（系统重签方式可能改变身份；不要先删原 App）。
2. 确认地图、定位和恢复仍正常。
3. 设置 → 签名与应用管理，确认描述文件有效期；小火箭开启指定设备路由，关闭 LocalDevVPN，恢复真实定位后检查 RSD / AFC / InstallationProxy。
4. Wi-Fi 和 5G 分别记录四个检查结果；如果只通过 RSD，不能宣称安装可用。必要时用 LocalDevVPN 对照。底层 FFI 调用尚无可取消超时保证。
5. 导入自己的测试 IPA，检查哈希、重启后暂存记录和删除；查看 GitHub 正式发布检查结果。
6. 只有安装服务连接及后续实际安装试验完成后，才接入签名和自身更新。

## 下一阶段尚未完成
Apple Account / 2FA / Anisette、证书申请和保存、签署 Mach-O 与嵌套扩展、AFC 上传、InstallationProxy 安装、安装后描述文件核验、自身续签、后台续签、可信更新清单、动态 RSD 发现、全面真机验收。

技术调研：现有 Locus 固定 idevice 头文件明确包含 afc_client_connect_rsd 和 installation_proxy_connect_rsd。SideSign README 声明 GPL-3.0，SideStore 为 AGPL-3.0；SideSign 还依赖多个浮动分支，实际接入前须审查依赖许可证、固定版本及构建条件。此分支暂未引入两者代码，保持现有许可证；后续引入签名库须按实际合规方案处理。参考：
- https://github.com/SideStore/SideSign
- https://github.com/SideStore/SideStore
- https://github.com/ChrisMack32/Locus/blob/83c8fb324983728e8f44759cfd834dc637ee38b5/Vendor/idevice/idevice.h

## Build 23 链接失败与 Build 24 修复
R40 的源码和回归检查通过，但 arm64 链接失败：`afc_client_connect_rsd`、`afc_client_free` 在现有预编译静态库中缺失。头文件存在声明不代表库存在实现。Build 24 使用 macOS nm 检查实际导出符号，分别按能力启用 AFC 与 InstallationProxy 调用；不支持时界面明确标记底层库未提供接口，而非伪造连接成功。未改变原有 idevice 版本，完整 AFC 支持仍需补齐兼容的依赖库并在真机验证。重新构建结果以 Actions 为准。
