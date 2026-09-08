import BRBluetoothLib
import CoreBluetooth
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BRDemoViewModel: ObservableObject {
    @Published var peripherals: [BRDemoPeripheral] = []
    @Published var selectedPeripheralID: UUID?
    @Published var connectionText = "未连接"
    @Published var bluetoothStateText = "未知"
    @Published var wifiText = "未连接"
    @Published var socketText = "未连接"
    @Published var deviceText = ""
    @Published var files: [BRAudioFileInfo] = []
    @Published var selectedFileName = ""
    @Published var earphoneMac = ""
    @Published var phoneMac = ""
    @Published var bleOtaURL: URL?
    @Published var wifiOtaURL: URL?
    @Published var progressText = ""
    @Published var logLines: [String] = []

    let bridge = BRDemoBluetoothBridge()
    private let sdk = BrBluetoothManager.shared
    private let syncObserver = BRDemoSyncObserver()
    private var peripheralSNCache: [UUID: String] = [:]

    init() {
        bridge.delegate = self
        sdk.setDelegate(self)
        sdk.setLogger(self)
        sdk.configure(BRSDKConfiguration(syncRootDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first))
        seedPeripheralSNCache()
        syncObserver.onProgress = { [weak self] progress in
            Task { @MainActor in
                self?.progressText = "\(progress.file) \(progress.receivedBytes)/\(progress.totalBytes) bytes, frame \(progress.lastFrameIndex)"
            }
        }
    }

    var selectedPeripheral: BRDemoPeripheral? {
        peripherals.first { $0.id == selectedPeripheralID }
    }

    func startScan() {
        appendLog("开始扫描 BLE 设备")
        peripherals.removeAll()
        bridge.startScan()
    }

    func stopScan() {
        bridge.stopScan()
        appendLog("停止扫描")
    }

    func connectSelected() {
        guard let selectedPeripheral else {
            appendLog("请先选择设备")
            return
        }
        run("BLE 连接并握手") { [self] in
            try await bridge.connect(selectedPeripheral)
            let info = try await sdk.phoneBluetoothManager.connect(selectedPeripheral.sdkDevice)
            connectionText = "已连接：\(info.device.name ?? selectedPeripheral.name)"
            if let detail = info.handshakeInfo {
                deviceText = Self.formatDeviceDetail(detail)
            }
        }
    }

    func reconnectLastBoundDevice() {
        run("回连上次绑定设备") { [self] in
            let device = try await bridge.connectLastBoundDevice()
            let info = try await sdk.phoneBluetoothManager.connect(device)
            connectionText = "已回连：\(info.device.name ?? "-")"
            if let detail = info.handshakeInfo {
                deviceText = Self.formatDeviceDetail(detail)
            }
        }
    }

    func disconnect() {
        run("断开 BLE") { [self] in
            try await sdk.phoneBluetoothManager.disconnect()
            bridge.disconnect()
            connectionText = "未连接"
        }
    }

    func syncTime() {
        run("同步手机时间") { [self] in
            let echoed = try await sdk.deviceNormalManager.syncTime()
            appendLog("设备回显时间：\(echoed)")
        }
    }

    func fetchBasicDeviceInfo() {
        run("读取设备基础信息") { [self] in
            async let battery = sdk.deviceNormalManager.getBatteryLevel()
            async let sn = sdk.deviceNormalManager.getDeviceSN()
            async let gain = sdk.deviceNormalManager.getMicGain()
            async let storage = sdk.deviceNormalManager.getStorageCapacity()
            async let shutdown = sdk.deviceNormalManager.getAutoShutdownTime()
            async let switchStatus = sdk.deviceNormalManager.getSwitchStatus()
            async let storageDisabled = sdk.deviceNormalManager.getStorageDisableStatus()
            async let wavDisabled = sdk.deviceNormalManager.getWavDisableStatus()
            async let recordScreensaver = sdk.deviceNormalManager.getRecordScreensaverTime()
            let version = try await sdk.deviceNormalManager.getDeviceVersionInfo()
            let storageInfo = try await storage
            deviceText = """
            SN: \(try await sn)
            电量: \(try await battery)%
            Mic 增益: \(try await gain)
            存储: \(storageInfo.freeCapacity)/\(storageInfo.totalCapacity) \(storageInfo.unit)
            自动关机: \(try await shutdown) 分钟
            拨动开关: \(try await switchStatus)
            禁用存储: \(try await storageDisabled)
            禁用 WAV: \(try await wavDisabled)
            录音屏保: \(try await recordScreensaver) 分钟
            版本: BLE v\(version.softwareVersion).\(version.softwareVersionPatch), WiFi v\(version.wifiSoftwareVersion).\(version.wifiSoftwareVersionPatch)
            """
        }
    }

    func setMicGainMax() {
        run("设置 mic 增益为 19") { [self] in
            let gain = try await sdk.deviceNormalManager.setMicGain(gain: 19)
            appendLog("Mic 增益设置结果：\(gain)")
        }
    }

    func setAutoShutdownFiveMinutes() {
        run("设置 5 分钟无操作关机") { [self] in
            let minutes = try await sdk.deviceNormalManager.setAutoShutdownTime(minutes: 5)
            appendLog("自动关机时间：\(minutes) 分钟")
        }
    }

    func setRecordScreensaverOneMinute() {
        run("设置录音屏保 1 分钟") { [self] in
            let minutes = try await sdk.deviceNormalManager.setRecordScreensaverTime(minutes: 1)
            appendLog("录音屏保时间：\(minutes) 分钟")
        }
    }

    func disableStorage(_ disabled: Bool) {
        run(disabled ? "禁用存储" : "恢复存储") { [self] in
            let success = try await sdk.deviceNormalManager.setStorageDisable(disabled)
            appendLog("存储开关结果：\(success)")
        }
    }

    func disableWav(_ disabled: Bool) {
        run(disabled ? "禁用 WAV" : "恢复 WAV") { [self] in
            let success = try await sdk.deviceNormalManager.setWavDisable(disabled)
            appendLog("WAV 开关结果：\(success)")
        }
    }

    func formatDevice() {
        run("格式化设备") { [self] in
            let success = try await sdk.deviceNormalManager.formatDevice()
            appendLog("格式化结果：\(success)")
        }
    }

    func deleteSelectedFile() {
        let fileName = selectedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            appendLog("请先选择或输入文件名")
            return
        }
        run("删除文件 \(fileName)") { [self] in
            let success = try await sdk.deviceNormalManager.deleteDeviceFile(fileName: fileName)
            appendLog("删除结果：\(success)")
        }
    }

    func unbindDevice(deleteAudio: Bool) {
        run(deleteAudio ? "解绑并删除音频" : "解绑设备") { [self] in
            try await sdk.deviceNormalManager.unbindDevice(deleteAudio: deleteAudio)
            connectionText = "已解绑"
        }
    }

    func startRecording() {
        run("开始 BLE 实时录音") { [self] in
            let info = try await sdk.bleAudioManager.startRecording()
            selectedFileName = info.file
            appendLog("录音文件：\(info.file)")
        }
    }

    func pauseRecording() {
        run("暂停录音") { [self] in
            appendLog("暂停结果：\(try await sdk.bleAudioManager.pauseRecording())")
        }
    }

    func resumeRecording() {
        run("恢复录音") { [self] in
            appendLog("恢复结果：\(try await sdk.bleAudioManager.resumeRecording())")
        }
    }

    func stopRecording() {
        run("停止录音") { [self] in
            let result = try await sdk.bleAudioManager.stopRecording()
            appendLog("停止录音 CRC：\(result.crc.map(String.init) ?? "-")")
        }
    }

    func fetchBleFiles() {
        run("BLE 获取文件列表") { [self] in
            files = try await sdk.bleAudioSyncManager.fetchBleFileList()
            selectedFileName = files.first?.file ?? selectedFileName
            appendLog("BLE 文件数：\(files.count)")
        }
    }

    func syncSelectedFileByBle() {
        guard let file = selectedFile() else { return }
        run("BLE 同步 \(file.file)") { [self] in
            let result = try await sdk.bleAudioSyncManager.startBleSyncOne(file, observer: syncObserver)
            appendLog("BLE 同步完成：\(result.localFile.lastPathComponent), success=\(result.success)")
        }
    }

    func syncAllFilesByBle() {
        run("BLE 队列同步") { [self] in
            let source = files.isEmpty ? try await sdk.bleAudioSyncManager.fetchBleFileList() : files
            let results = try await sdk.bleAudioSyncManager.startBleSyncQueue(source, observer: syncObserver)
            appendLog("BLE 队列完成：\(results.count) 个文件")
        }
    }

    func openWifiAndSocket() {
        run("打开 WiFi 并连接 socket") { [self] in
            let hotspot = try await sdk.phoneWifiManager.openWifi()
            wifiText = "\(hotspot.ssid) / \(hotspot.password)"
            _ = try await sdk.phoneWifiManager.connectDeviceWifi(hotspot)
            try await sdk.phoneWifiManager.openSocket()
            socketText = "socket 已连接"
        }
    }

    func querySocketStatus() {
        run("查询 socket 状态") { [self] in
            let status = try await sdk.phoneWifiManager.querySocketStatus()
            socketText = status.isConnected ? "socket 已连接" : "socket 未连接：\(status.rawStatus)"
        }
    }

    func closeWifi() {
        run("关闭 WiFi") { [self] in
            try await sdk.phoneWifiManager.closeWifi()
            wifiText = "未连接"
            socketText = "未连接"
        }
    }

    func fetchWifiFiles() {
        run("WiFi 获取文件列表") { [self] in
            files = try await sdk.wifiSyncManager.fetchFileList()
            selectedFileName = files.first?.file ?? selectedFileName
            appendLog("WiFi 文件数：\(files.count)")
        }
    }

    func syncSelectedFileByWifi() {
        guard let file = selectedFile() else { return }
        run("WiFi 同步 \(file.file)") { [self] in
            let result = try await sdk.wifiSyncManager.startSyncOne(file, observer: syncObserver)
            appendLog("WiFi 同步完成：\(result.localFile.lastPathComponent), success=\(result.success)")
        }
    }

    func resumeSelectedFileByWifi() {
        guard let file = selectedFile() else { return }
        run("WiFi 断点续传 \(file.file)") { [self] in
            let resume = BRWifiResumeInfo(fileName: file.file, index: 0, crc: 0)
            let result = try await sdk.wifiSyncManager.startResumeSync(fileInfo: file, resumeInfo: resume, observer: syncObserver)
            appendLog("WiFi 续传完成：\(result.localFile.lastPathComponent), success=\(result.success)")
        }
    }

    func syncAllFilesByWifi() {
        run("WiFi 队列同步") { [self] in
            let source = files.isEmpty ? try await sdk.wifiSyncManager.fetchFileList() : files
            let results = try await sdk.wifiSyncManager.startSyncQueue(source, observer: syncObserver)
            appendLog("WiFi 队列完成：\(results.count) 个文件")
        }
    }

    func setBleOtaURL(_ result: Result<[URL], Error>) {
        if case let .success(urls) = result {
            bleOtaURL = urls.first
        }
    }

    func setWifiOtaURL(_ result: Result<[URL], Error>) {
        if case let .success(urls) = result {
            wifiOtaURL = urls.first
        }
    }

    func startOta() {
        guard let bleOtaURL, let wifiOtaURL else {
            appendLog("请先选择 BLE 和 WiFi 两个 ufw 包")
            return
        }
        run("WiFi OTA") { [self] in
            let packageSet = BROtaPackageSetInfo(
                blePackage: BROtaPackageInfo(fileURL: bleOtaURL, chipType: .ble),
                wifiPackage: BROtaPackageInfo(fileURL: wifiOtaURL, chipType: .wifi)
            )
            let result = try await sdk.wifiOtaManager.startOta(packageSet: packageSet) { [weak self] progress in
                Task { @MainActor in
                    self?.progressText = "OTA \(progress.stage.rawValue) \(Int(progress.progress * 100))%"
                }
            }
            appendLog("OTA 完成：\(result.success)")
        }
    }

    func cancelOta() {
        run("取消 OTA") { [self] in
            try await sdk.wifiOtaManager.cancelOta()
        }
    }

    func enableEarphoneMode() {
        run("开启耳机模式") { [self] in
            let result = try await sdk.earphoneModeManager.setEarphoneMode(enabled: true, earphoneMac: earphoneMac, phoneMac: phoneMac)
            appendLog("耳机模式：available=\(result.commandAvailable), earphoneAction=\(result.earphoneAction), phoneAction=\(result.phoneAction)")
        }
    }

    func disableEarphoneMode() {
        run("关闭耳机模式") { [self] in
            let result = try await sdk.earphoneModeManager.setEarphoneMode(enabled: false)
            appendLog("耳机模式关闭：available=\(result.commandAvailable)")
        }
    }

    func connectEarphone() {
        let mac = earphoneMac.trimmingCharacters(in: .whitespacesAndNewlines)
        run("连接指定耳机") { [self] in
            try await sdk.earphoneModeManager.connectEarphone(mac: mac)
            appendLog("已发送耳机连接请求：\(mac)")
        }
    }

    func queryEarphoneStatus() {
        run("查询耳机连接状态") { [self] in
            let result = try await sdk.earphoneModeManager.queryConnectionStatus()
            appendLog("经典蓝牙=\(result.classicBluetoothEnabled), 耳机=\(result.earphoneStatus), 手机=\(result.phoneStatus)")
        }
    }

    func queryEarphoneHistory() {
        run("查询历史 MAC") { [self] in
            let result = try await sdk.earphoneModeManager.queryHistoryMac()
            earphoneMac = result.earphoneMac
            phoneMac = result.phoneMac
            appendLog("历史 MAC：earphone=\(result.earphoneMac), phone=\(result.phoneMac)")
        }
    }

    func clearEarphoneHistory() {
        run("清空历史 MAC") { [self] in
            _ = try await sdk.earphoneModeManager.queryHistoryMac(clear: true)
            appendLog("已请求清空历史 MAC")
        }
    }

    func queryClassicBluetoothName() {
        run("查询经典蓝牙名称") { [self] in
            let name = try await sdk.earphoneModeManager.queryClassicBluetoothName()
            appendLog("经典蓝牙名称：\(name)")
        }
    }

    func flashIdeaStatus() {
        switch sdk.flashIdeaManager.getFlashIdeaStatus() {
        case .idle:
            appendLog("闪念状态：idle")
        case let .start(info):
            appendLog("闪念进行中：\(info.file)")
        case let .stop(result):
            appendLog("闪念结束：\(result.info?.file ?? "-")")
        case let .error(message):
            appendLog("闪念错误：\(message)")
        }
    }

    private func run(_ title: String, operation: @escaping () async throws -> Void) {
        appendLog("开始：\(title)")
        Task {
            do {
                try await operation()
                appendLog("完成：\(title)")
            } catch {
                appendLog("失败：\(title) - \(error.localizedDescription)")
            }
        }
    }

    private func selectedFile() -> BRAudioFileInfo? {
        if let exact = files.first(where: { $0.file == selectedFileName }) {
            return exact
        }
        appendLog("请先从文件列表选择文件")
        return nil
    }

    private func appendLog(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        logLines.insert("[\(stamp)] \(message)", at: 0)
        if logLines.count > 200 {
            logLines.removeLast(logLines.count - 200)
        }
    }

    private static func formatDeviceDetail(_ detail: BRDeviceDetailInfo) -> String {
        """
        名称: \(detail.name)
        SN: \(detail.sn)
        UUID: \(detail.uuid)
        品牌/型号: \(detail.brand) / \(detail.model)
        设备版本: \(detail.deviceVersion)
        连接前录音中: \(detail.isAudioRecorded)
        屏幕: \(detail.screen)
        WiFi SSID: \(detail.wifiSsid)
        """
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension BRDemoViewModel: BRDemoBluetoothBridgeDelegate {
    func bridgeDidUpdateState(_ state: CBManagerState) {
        bluetoothStateText = "\(state.rawValue)"
    }

    func bridgeDidDiscover(_ device: BRDemoPeripheral) {
        let merged = device.with(sn: peripheralSNCache[device.id])
        peripherals.removeAll { $0.id == device.id }
        peripherals.append(merged)
    }

    func bridgeDidConnect(_ peripheral: CBPeripheral) {
        connectionText = "BLE 已连接，发现服务中"
    }

    func bridgeDidDisconnect(_ peripheral: CBPeripheral?, error: Error?) {
        connectionText = "BLE 已断开"
        if let error {
            appendLog("BLE 断开：\(error.localizedDescription)")
        }
    }

    func bridgeDidFail(_ message: String) {
        appendLog("BLE 桥接错误：\(message)")
    }
}

extension BRDemoViewModel: BRSDKDelegate {
    nonisolated func bluetoothSDKDidEmit(event: BRSDKEvent) {
        Task { @MainActor in
            switch event {
            case let .bluetoothStateChanged(state):
                bluetoothStateText = state.rawValue
            case let .deviceDiscovered(device):
                appendLog("SDK 发现设备：\(device.name ?? device.identifier)")
            case let .deviceConnected(device):
                connectionText = "SDK 已连接：\(device.name ?? device.identifier)"
                cacheSN(device.detailInfo?.sn, for: device.identifier)
            case let .deviceDisconnected(info):
                connectionText = "SDK 已断开：\(info.reason ?? "-")"
            case let .boundDeviceSaved(info):
                appendLog("已保存绑定：\(info.deviceName) / \(info.deviceSN)")
            case .boundDeviceRemoved:
                appendLog("已删除绑定")
            case let .wifiStateChanged(state):
                wifiText = state.rawValue
            case let .socketStatusChanged(status):
                socketText = status.isConnected ? "socket 已连接" : "socket 状态 \(status.rawStatus)"
            case let .recordStarted(info):
                selectedFileName = info.file
                appendLog("录音开始：\(info.file), type=\(info.fileType)")
            case let .recordStopped(result):
                appendLog("录音停止：crc=\(result.crc.map(String.init) ?? "-")")
            case let .audioFrame(packet):
                progressText = "实时音频 frame \(packet.frameIndex ?? 0), \(packet.payload.count) bytes"
            case let .fileSyncProgress(progress):
                progressText = "\(progress.file) \(progress.receivedBytes)/\(progress.totalBytes)"
            case let .singleFileSyncFinished(result):
                appendLog("文件同步完成：\(result.fileInfo.file)")
            case let .realtimeSyncFinished(result):
                appendLog("实时录音保存：\(result.localFile?.lastPathComponent ?? result.file), success=\(result.success)")
            case let .flashIdeaStarted(result):
                appendLog("闪念开始：\(result.startInfo?.file ?? result.errorMessage ?? "-")")
            case let .flashIdeaData(info, packet):
                progressText = "闪念 \(info.file) frame \(packet.frameIndex ?? 0)"
            case let .flashIdeaEnded(result):
                appendLog("闪念结束：\(result.info?.file ?? "-"), crc=\(result.crc.map(String.init) ?? "-")")
            case let .fileMarked(mark):
                appendLog("MARK：type=\(mark.type), time=\(mark.time)")
            case let .otaProgress(progress):
                progressText = "OTA \(progress.stage.rawValue) \(Int(progress.progress * 100))%"
            case let .otaFinished(result):
                appendLog("OTA 结束：success=\(result.success), error=\(result.errorMessage ?? "-")")
            case let .earphoneScanned(result):
                if !result.mac.isEmpty {
                    earphoneMac = result.mac
                }
                appendLog("扫描耳机：\(result.name) \(result.mac), status=\(result.status)")
            case let .earphoneConnectionChanged(result):
                appendLog("耳机连接状态：classic=\(result.classicBluetoothEnabled), earphone=\(result.earphoneStatus), phone=\(result.phoneStatus)")
            }
        }
    }

    private func seedPeripheralSNCache() {
        for boundDevice in sdk.phoneBluetoothManager.getBoundDevices() {
            guard let id = UUID(uuidString: boundDevice.peripheralIdentifier),
                  !boundDevice.deviceSN.isEmpty else {
                continue
            }
            peripheralSNCache[id] = boundDevice.deviceSN
        }
    }

    private func cacheSN(_ sn: String?, for identifier: String) {
        let trimmed = sn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let id = UUID(uuidString: identifier) else { return }
        peripheralSNCache[id] = trimmed
        if let index = peripherals.firstIndex(where: { $0.id == id }) {
            peripherals[index] = peripherals[index].with(sn: trimmed)
        }
    }
}

extension BRDemoViewModel: BRSDKLogger {
    nonisolated func bluetoothSDKLog(level: BRSDKLogLevel, tag: String, message: String, error: Error?) {
        Task { @MainActor in
            appendLog("\(level.rawValue) \(tag): \(message)\(error.map { " - \($0.localizedDescription)" } ?? "")")
        }
    }
}

private final class BRDemoSyncObserver: FileSyncObserver {
    var onProgress: ((BRFileSyncProgress) -> Void)?

    func onFileSyncProgress(_ progress: BRFileSyncProgress) {
        onProgress?(progress)
    }
}

extension UTType {
    static let brUfw = UTType(filenameExtension: "ufw") ?? .data
}
