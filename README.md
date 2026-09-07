# ble-iOS

百融录音卡 iOS BLE/WiFi 协议层 SDK，模块名为 `BRBluetoothLib`。

本仓库按协议文档重新建设，参考 `/Users/admin/bairongble-ios` 的分层方式，但协议行为以 `T240_BLE_WIFI_通信协议_20250906.md` 为准。

## 分层

- `BrBluetoothManager`：SDK 总入口，组装 BLE、WiFi、设备指令、音频同步、OTA、闪念和耳机模式。
- `Core`：命令执行、响应匹配、主动上报路由、日志、错误和事件代理。
- `Protocol`：命令码、帧模型、BLE/WiFi 编解码、CRC、payload 和业务模型。
- `Ble` / `Wifi`：平台传输、扫描连接、热点和 socket 通道。
- `Device`：时间、电量、SN、设备信息、存储、增益、解绑和配置类指令。
- `Audio` / `Synchro`：实时录音、BLE/WiFi 文件同步、闪念、MARK 和耳机模式。
- `Ota`：WiFi OTA 检测、分包、确认、进度和取消。
- `Classic`：经典蓝牙能力占位，服务耳机通话录音模式。

## 验证

```bash
swift test
```
