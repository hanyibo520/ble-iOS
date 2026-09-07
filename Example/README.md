# BRBluetoothLibDemo

这是一个可以直接打开运行的 iOS demo 工程，结构参考 `/Users/admin/bairongble-ios/Example`。

打开方式：

```bash
open /Users/admin/ble-iOS/Example/BRBluetoothLibDemo.xcodeproj
```

然后在 Xcode 里选择 `BRBluetoothLibDemo` scheme 和真实 iPhone 运行。BLE 和热点能力需要真机；模拟器只能做编译和 UI 预览，不能完成真实设备连接。

工程使用本地 Swift Package 依赖当前仓库的 `BRBluetoothLib`，不需要先执行 `pod install`。
