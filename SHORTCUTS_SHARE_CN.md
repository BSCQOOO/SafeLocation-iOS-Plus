# Apple 地图分享到 Safe Location（快捷指令）

iOS 的 Share Extension 没有稳定、公开的方式直接强制拉起包含它的主 App。Safe Location 1.1 因此采用 Apple 官方 App Intents + 快捷指令路线。

## 一次设置

1. 打开「快捷指令」App，新建快捷指令。
2. 在动作里搜索 **Safe Location**。
3. 选择 **导入地图位置**，或者 **Teleport 到地图位置**。
4. 将动作里的「地图链接、地点或坐标」参数设为 **快捷指令输入**。
5. 打开快捷指令详情，开启 **在共享表单中显示**。
6. 接收类型选择 **URL** 和 **文本**。
7. 把快捷指令命名为「Safe Location」。

## 使用

Apple 地图 → 打开地点 → 分享 → 选择刚才的「Safe Location」快捷指令。

- **导入地图位置**：打开 Safe Location 并选中位置，不自动 Teleport。
- **Teleport 到地图位置**：如果 RPPairing 与 LocalDevVPN 已经就绪，会直接 Teleport；否则只导入位置并提示缺少的条件。

也可以在 Google 地图、Safari 或其他能分享地图 URL / 文字地址的 App 中使用同一快捷指令。
