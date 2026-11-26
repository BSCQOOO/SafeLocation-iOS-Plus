# SafeLocation 通用隧道开发分支

## 安装与设置（待验证）
本分支保留 LocalDevVPN，新增 Shadowrocket。默认仍为 LocalDevVPN，避免升级影响原有连接。无需为主 App 添加 Network Extension entitlement。Shadowrocket 模式固定使用 10.7.0.1；只允许在会话结束后切换客户端，异常恢复时允许切换以恢复连接。首次设置及设置页面均提供选择。

在小火箭的 设置 → 其它 开启“包含路由 10.7.0.1/32”，断开再连接小火箭，回到 SafeLocation 选择 Shadowrocket 并在诊断中检测设备通道，再在自己控制的测试设备上进行定位测试。TCP 可达不表示配对认证成功或 DVT 可用；真正的定位设置仍由现有加密配对/DVT 引擎完成。不需要同时开启 LocalDevVPN。若不可达，请首先使用 Wi-Fi 复测，再试蜂窝数据。没有验证的情况下不能宣称 5G 可用。

## 验收记录（全部待真机）
| 场景 | 验收标准 |
|---|---|
| Shadowrocket + Wi-Fi | 原有互联网代理正常；诊断可达；真实 DVT 设置成功；恢复后互联网仍正常 |
| Shadowrocket + 5G | 同上；如失败记录阶段，不能只凭 utun 判断 |
| Wi-Fi/5G 切换、节点切换 | 不误报成功，能够恢复真实定位 |
| LocalDevVPN 回归 | 旧配对仍有效；固定、路线、摇杆、恢复 |
| 恢复保护 | 运行路线后恢复，不被旧计时器重新写入；意外退出后提示并显式恢复 |
| 坐标 | 长野西部/东部、东京、北京、首尔；地图选点、搜索、经纬度、链接、快捷调用与道路路线分别验证；对照实际 WGS 坐标 |
| 搜索 | 地图视野作为提示而非限制；输入新词/清空/取消时不显示旧结果 |
| 抽屉 | 收起、键盘、设置子页、前后台、摇杆、异常恢复面板无失踪或重叠 |
| 路线 | 开始、停止、替换路线，进度按距离；GPX 导出再导入 |
| 自动恢复 | 固定、路线、摇杆均检查定时，系统终止后不保证按时自动执行 |

## 验证与限制
源码结构检查已更新，macOS 上运行 `bash Scripts/quality_check.sh` 会执行坐标和 GPX 断言；`bash Scripts/build_unsigned_ipa.sh` 需要 Apple SDK 和 XcodeGen。当前未运行 Xcode 编译、未生成 IPA、未真机测试。日本修复是针对已知误判区域及搜索国家代码的保护，并非完整的精确国界模型；手动 WGS-84 / GCJ-02 可用于排查。Apple 地图服务区域的自动识别仍是启发式，需真机验证。

参考公开功能文档：[Shadowrocket integration](https://github.com/suversal/WrapPin/blob/main/Documentation/ShadowrocketIntegration.zh-CN.md)。本分支独立实现，无第三方非商业源码引入。未添加分析 SDK、未上传位置或配对数据。其他 VPN 客户端未接入，未恢复自动 GitHub Actions 工作流。
