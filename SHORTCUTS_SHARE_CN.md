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


## 纯蜂窝 Developer Tunnel 实验

Safe Location 的实验分支支持没有 Wi-Fi / 热点时，通过 LocalDevVPN + 飞行模式建立本机 Developer Tunnel。

### 一次设置

在系统「快捷指令」App 新建两个快捷指令：

1. **SafeLocation Airplane On**：只添加一个“设置飞行模式”动作，设为**打开**。
2. **SafeLocation Airplane Off**：只添加一个“设置飞行模式”动作，设为**关闭**。

名称也可以在 Safe Location → 设置 → 纯蜂窝实验中修改。

> 不要把第一个快捷指令做成“关闭蜂窝数据”。无 Wi-Fi 路径需要先保持 4G/5G 可用并连接 LocalDevVPN，再临时打开飞行模式，让本机 utun 路由继续用于 RPPairing / RSD / DVT。

### 使用流程

关闭 Wi-Fi，只保留 4G/5G，然后正常在 Safe Location 点 Teleport。App 会执行：

Safe Location → LocalDevVPN → SafeLocation Airplane On → Safe Location → RPPairing / RSD / DVT → SafeLocation Airplane Off → Safe Location。

Safe Location 使用 Shortcuts x-callback-url 自动返回。如果 Shortcuts 的回调丢失，App 回到前台后还会检查物理蜂窝接口与 LocalDevVPN utun：飞行模式已经成功且 utun 仍存在时会继续建链，否则会直接给出明确错误，不再让流程挂起。

如果系统「快捷指令」列表为空，请先完成上面的两个快捷指令再测试纯蜂窝模式。
