import BRBluetoothLib
import SwiftUI
import UniformTypeIdentifiers

struct BRDemoContentView: View {
    @ObservedObject var viewModel: BRDemoViewModel
    @State private var importBleOta = false
    @State private var importWifiOta = false

    var body: some View {
        NavigationView {
            List {
                connectionSection
                scanResultsSection
                deviceSection
                recordingSection
                bleSyncSection
                wifiSection
                otaSection
                flashIdeaSection
                earphoneSection
                logSection
            }
            .navigationTitle("BRBluetooth Demo")
            .fileImporter(isPresented: $importBleOta, allowedContentTypes: [.brUfw], allowsMultipleSelection: false) { result in
                viewModel.setBleOtaURL(result)
            }
            .fileImporter(isPresented: $importWifiOta, allowedContentTypes: [.brUfw], allowsMultipleSelection: false) { result in
                viewModel.setWifiOtaURL(result)
            }
        }
    }

    private var connectionSection: some View {
        Section(header: Text("连接和握手")) {
            HStack {
                Button("扫描") { viewModel.startScan() }
                Button("停止") { viewModel.stopScan() }
                Button("回连") { viewModel.reconnectLastBoundDevice() }
                Button("断开") { viewModel.disconnect() }
            }
            .buttonStyle(.borderless)
            Text("蓝牙：\(viewModel.bluetoothStateText)")
            Text("连接：\(viewModel.connectionText)")
        }
    }

    private var scanResultsSection: some View {
        Section(header: Text("扫描结果")) {
            if viewModel.peripherals.isEmpty {
                Text("暂无扫描结果")
                    .foregroundColor(.secondary)
            } else {
                Text("共 \(viewModel.peripherals.count) 台卡片")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                ForEach(viewModel.peripherals) { device in
                    Button {
                        viewModel.selectedPeripheralID = device.id
                        viewModel.connectSelected()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.displayTitle)
                                Text(device.detailLine)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("RSSI \(device.rssi)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("连接")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var deviceSection: some View {
        Section(header: Text("普通指令")) {
            Button("同步时间 0x04") { viewModel.syncTime() }
            Button("读取电量/SN/容量/版本/状态") { viewModel.fetchBasicDeviceInfo() }
            Button("设置 mic 增益 19") { viewModel.setMicGainMax() }
            Button("设置 5 分钟自动关机") { viewModel.setAutoShutdownFiveMinutes() }
            Button("设置录音屏保 1 分钟") { viewModel.setRecordScreensaverOneMinute() }
            HStack {
                Button("禁用存储") { viewModel.disableStorage(true) }
                Button("恢复存储") { viewModel.disableStorage(false) }
            }
            .buttonStyle(.borderless)
            HStack {
                Button("禁用 WAV") { viewModel.disableWav(true) }
                Button("恢复 WAV") { viewModel.disableWav(false) }
            }
            .buttonStyle(.borderless)
            TextField("文件名，例如 R20240607-121212.opus", text: $viewModel.selectedFileName)
                .autocapitalization(.none)
            Button("删除文件 0x1E") { viewModel.deleteSelectedFile() }
            Button("格式化设备 0x68") { viewModel.formatDevice() }
                .foregroundColor(.red)
            HStack {
                Button("解绑") { viewModel.unbindDevice(deleteAudio: false) }
                Button("解绑并删除音频") { viewModel.unbindDevice(deleteAudio: true) }
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            if !viewModel.deviceText.isEmpty {
                Text(viewModel.deviceText).font(.footnote)
            }
        }
    }

    private var recordingSection: some View {
        Section(header: Text("BLE 实时录音")) {
            HStack {
                Button("开始") { viewModel.startRecording() }
                Button("暂停") { viewModel.pauseRecording() }
                Button("恢复") { viewModel.resumeRecording() }
                Button("停止") { viewModel.stopRecording() }
            }
            .buttonStyle(.borderless)
            Text(viewModel.progressText).font(.footnote).foregroundColor(.secondary)
        }
    }

    private var bleSyncSection: some View {
        Section(header: Text("BLE 本地同步")) {
            Button("获取 BLE 文件列表") { viewModel.fetchBleFiles() }
            filePicker
            HStack {
                Button("同步选中文件") { viewModel.syncSelectedFileByBle() }
                Button("同步全部") { viewModel.syncAllFilesByBle() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var wifiSection: some View {
        Section(header: Text("WiFi 通道和同步")) {
            Button("打开 WiFi 并连接 socket") { viewModel.openWifiAndSocket() }
            Button("查询 socket") { viewModel.querySocketStatus() }
            Button("关闭 WiFi") { viewModel.closeWifi() }
            Text("WiFi：\(viewModel.wifiText)")
            Text("Socket：\(viewModel.socketText)")
            Button("获取 WiFi 文件列表") { viewModel.fetchWifiFiles() }
            filePicker
            HStack {
                Button("WiFi 同步选中") { viewModel.syncSelectedFileByWifi() }
                Button("断点续传") { viewModel.resumeSelectedFileByWifi() }
                Button("WiFi 同步全部") { viewModel.syncAllFilesByWifi() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var otaSection: some View {
        Section(header: Text("WiFi OTA")) {
            Button(viewModel.bleOtaURL?.lastPathComponent ?? "选择 BLE ufw") { importBleOta = true }
            Button(viewModel.wifiOtaURL?.lastPathComponent ?? "选择 WiFi ufw") { importWifiOta = true }
            HStack {
                Button("开始 OTA") { viewModel.startOta() }
                Button("取消 OTA") { viewModel.cancelOta() }
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var flashIdeaSection: some View {
        Section(header: Text("闪念和 MARK")) {
            Button("读取闪念状态") { viewModel.flashIdeaStatus() }
            Text("0xB0/0xB1/0xB2 与 0xB3 的设备主动上报会显示在日志中。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var earphoneSection: some View {
        Section(header: Text("耳机通话录音")) {
            TextField("耳机 MAC，12 字符", text: $viewModel.earphoneMac)
                .autocapitalization(.allCharacters)
            TextField("手机 MAC，12 字符", text: $viewModel.phoneMac)
                .autocapitalization(.allCharacters)
            HStack {
                Button("开启耳机模式") { viewModel.enableEarphoneMode() }
                Button("关闭耳机模式") { viewModel.disableEarphoneMode() }
            }
            .buttonStyle(.borderless)
            HStack {
                Button("连接耳机") { viewModel.connectEarphone() }
                Button("查状态") { viewModel.queryEarphoneStatus() }
            }
            .buttonStyle(.borderless)
            HStack {
                Button("查历史 MAC") { viewModel.queryEarphoneHistory() }
                Button("清空历史") { viewModel.clearEarphoneHistory() }
                Button("经典蓝牙名") { viewModel.queryClassicBluetoothName() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var logSection: some View {
        Section(header: Text("事件日志")) {
            ForEach(viewModel.logLines, id: \.self) { line in
                Text(line).font(.caption)
            }
        }
    }

    private var filePicker: some View {
        Picker("文件", selection: $viewModel.selectedFileName) {
            Text("未选择").tag("")
            ForEach(viewModel.files, id: \.file) { file in
                Text("\(file.file) · \(file.fileType)").tag(file.file)
            }
        }
    }
}
