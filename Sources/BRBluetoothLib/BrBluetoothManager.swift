import Foundation

public final class BrBluetoothManager {
    public static let tag = "BrBluetoothManager"
    private static let sharedInstance = BrBluetoothManager()

    public class func getInstance(configuration: BRSDKConfiguration? = nil) -> BrBluetoothManager {
        if let configuration {
            sharedInstance.configure(configuration)
        }
        return sharedInstance
    }

    public static var shared: BrBluetoothManager { sharedInstance }
    public var configuration: BRSDKConfiguration { context.configuration }

    let context: BRSDKContext
    let protocolParser: BRProtocolParser
    let bleResponseMatcher: ResponseMatcher
    let wifiResponseMatcher: ResponseMatcher
    let blePacketRouter: InboundPacketRouter
    let wifiPacketRouter: InboundPacketRouter
    let bleTransport: BleTransport
    let wifiTransport: WifiTransport
    let bleCommandExecutor: CommandExecutor
    let wifiCommandExecutor: CommandExecutor
    let singleFileSynchro: SingleFileSynchro
    let realTimeSync: RealTimeSync
    let syncDirManager: SyncDirManager

    public let boundDeviceStore: BRBoundDeviceStore
    public let bluePermissionManager: BluePermissionManager
    public let wifiPermissionManager: WifiPermissionManager
    public let classicBluetoothPermissionManager: ClassicBluetoothPermissionManager
    public let blueScanManager: BlueScanManager
    public let phoneBluetoothManager: PhoneBluetoothManager
    public let phoneWifiManager: PhoneWifiManager
    public let deviceNormalManager: DeviceNormalManager
    public let bleAudioManager: BleAudioManager
    public let bleAudioSyncManager: BleAudioSyncManager
    public let wifiSyncManager: WifiAudioSyncManager
    public let wifiOtaManager: WifiOtaManager
    public let wifiOtaDebugManager: WifiOtaDebugManager
    public let flashIdeaManager: FlashIdeaManager
    public let fileMarkManager: FileMarkManager
    public let earphoneModeManager: EarphoneModeManager
    public let classicBluetoothManager: ClassicBluetoothManager

    private init() {
        let context = BRSDKContext()
        let parser = BRProtocolParser()
        let bleMatcher = ResponseMatcher(channel: .ble)
        let wifiMatcher = ResponseMatcher(channel: .wifi)
        let bleRouter = InboundPacketRouter()
        let wifiRouter = InboundPacketRouter()
        let bleTransport = BleTransport(context: context, parser: parser)
        let wifiTransport = WifiTransport(context: context, parser: parser)
        let bleExecutor = CommandExecutor(kind: .ble, transport: bleTransport, parser: parser, matcher: bleMatcher, router: bleRouter)
        let wifiExecutor = CommandExecutor(kind: .wifi, transport: wifiTransport, parser: parser, matcher: wifiMatcher, router: wifiRouter)
        let syncDirManager = SyncDirManager(context: context)
        let singleFileSynchro = SingleFileSynchro(context: context, syncDirManager: syncDirManager)
        let realTimeSync = RealTimeSync(context: context, syncDirManager: syncDirManager)
        let boundStore = BRBoundDeviceStore()

        self.context = context
        self.protocolParser = parser
        self.bleResponseMatcher = bleMatcher
        self.wifiResponseMatcher = wifiMatcher
        self.blePacketRouter = bleRouter
        self.wifiPacketRouter = wifiRouter
        self.bleTransport = bleTransport
        self.wifiTransport = wifiTransport
        self.bleCommandExecutor = bleExecutor
        self.wifiCommandExecutor = wifiExecutor
        self.syncDirManager = syncDirManager
        self.singleFileSynchro = singleFileSynchro
        self.realTimeSync = realTimeSync
        self.boundDeviceStore = boundStore

        self.bluePermissionManager = BluePermissionManager(context: context)
        self.wifiPermissionManager = WifiPermissionManager(context: context)
        self.classicBluetoothPermissionManager = ClassicBluetoothPermissionManager(context: context)
        self.blueScanManager = BlueScanManager(context: context)
        self.phoneBluetoothManager = PhoneBluetoothManager(context: context, transport: bleTransport, executor: bleExecutor, boundDeviceStore: boundStore)
        self.phoneWifiManager = PhoneWifiManager(executor: bleExecutor, wifiExecutor: wifiExecutor, context: context, wifiTransport: wifiTransport) { [weak phoneBluetoothManager] in
            phoneBluetoothManager?.getConnectDevice()
        }
        self.deviceNormalManager = DeviceNormalManager(executor: bleExecutor, context: context, boundDeviceStore: boundStore)
        self.bleAudioManager = BleAudioManager(executor: bleExecutor, context: context, realTimeSync: realTimeSync)
        self.bleAudioSyncManager = BleAudioSyncManager(executor: bleExecutor, context: context, singleFileSynchro: singleFileSynchro, syncDirManager: syncDirManager)
        self.wifiSyncManager = WifiAudioSyncManager(executor: wifiExecutor, context: context, singleFileSynchro: singleFileSynchro, syncDirManager: syncDirManager, closeWifi: { [weak phoneWifiManager] in
            _ = try await phoneWifiManager?.closeWifi()
        })
        self.wifiOtaManager = WifiOtaManager(executor: wifiExecutor, context: context)
        self.wifiOtaDebugManager = WifiOtaDebugManager(context: context)
        self.flashIdeaManager = FlashIdeaManager(context: context, realTimeSync: realTimeSync)
        self.fileMarkManager = FileMarkManager(context: context) { [weak bleAudioManager] in
            bleAudioManager?.getCurrentRecordStartInfo()
        }
        self.earphoneModeManager = EarphoneModeManager(executor: bleExecutor, context: context)
        self.classicBluetoothManager = ClassicBluetoothManager(context: context)

        bleTransport.setReceiveHandler { packet in _ = bleExecutor.receive(packet) }
        wifiTransport.setReceiveHandler { packet in _ = wifiExecutor.receive(packet) }
        phoneBluetoothManager.disconnectHandler = { [weak self] error, _ in self?.handleBleDisconnected(error) }
        registerPacketRoutes()
    }

    public func configure(_ configuration: BRSDKConfiguration) {
        context.updateConfiguration(configuration)
    }

    public func setDelegate(_ delegate: BRSDKDelegate?) {
        context.updateDelegate(delegate)
    }

    public func setLogger(_ logger: BRSDKLogger?) {
        context.updateLogger(logger)
    }

    public func reset() {
        bleCommandExecutor.cancelAll()
        wifiCommandExecutor.cancelAll()
        bleResponseMatcher.reset()
        wifiResponseMatcher.reset()
        bleAudioManager.reset()
        bleAudioSyncManager.reset()
        wifiSyncManager.reset()
        wifiOtaManager.reset()
        flashIdeaManager.reset()
        fileMarkManager.reset()
        singleFileSynchro.reset()
        realTimeSync.reset()
        registerPacketRoutes()
    }

    public func release() async {
        reset()
        await bleTransport.close()
        await wifiTransport.close()
    }

    private func registerPacketRoutes() {
        blePacketRouter.reset()
        wifiPacketRouter.reset()

        blePacketRouter.register(command: .switchStatusGet) { [weak self] packet in self?.deviceNormalManager.handleSwitchPush(packet) }
        blePacketRouter.register(command: .recordStart) { [weak self] packet in
            packet.isAudioFrame ? self?.bleAudioManager.handleRealtimeAudioPacket(packet) : self?.bleAudioManager.handleDevicePushOnRecordStart(packet)
        }
        blePacketRouter.register(command: .recordStop) { [weak self] packet in self?.bleAudioManager.handleDevicePushOnRecordStop(packet) }
        blePacketRouter.register(command: .getFileList) { [weak self] packet in self?.bleAudioSyncManager.handleFileListPacket(packet) }
        blePacketRouter.register(command: .syncFileData) { [weak self] packet in self?.bleAudioSyncManager.handleSyncAudioData(packet) }
        blePacketRouter.register(command: .syncStopCRC) { [weak self] packet in self?.bleAudioSyncManager.handleSyncStopCRC(packet) }
        blePacketRouter.register(command: .deleteFile) { [weak self] packet in self?.bleAudioSyncManager.handleDeviceDeleteFile(packet) }
        blePacketRouter.register(command: .flashIdeaStart) { [weak self] packet in self?.flashIdeaManager.handleFlashIdeaStart(packet) }
        blePacketRouter.register(command: .flashIdeaData) { [weak self] packet in self?.flashIdeaManager.handleFlashIdeaData(packet) }
        blePacketRouter.register(command: .flashIdeaStop) { [weak self] packet in self?.flashIdeaManager.handleFlashIdeaStop(packet) }
        blePacketRouter.register(command: .fileMark) { [weak self] packet in self?.fileMarkManager.handleFileMark(packet) }
        blePacketRouter.register(command: .earphoneScanReport) { [weak self] packet in self?.earphoneModeManager.handleScanReportPush(packet) }
        blePacketRouter.register(command: .earphoneConnectionStatus) { [weak self] packet in self?.earphoneModeManager.handleConnectionStatusPush(packet) }

        wifiPacketRouter.register(command: .getFileList) { [weak self] packet in self?.wifiSyncManager.handleFileListPacket(packet) }
        wifiPacketRouter.register(command: .syncFileData) { [weak self] packet in self?.wifiSyncManager.handleWifiFilePacket(packet) }
        wifiPacketRouter.register(command: .syncStopCRC) { [weak self] packet in self?.wifiSyncManager.handleSyncStopCRC(packet) }
        wifiPacketRouter.register(command: .socketStatus) { [weak self] packet in
            self?.context.emit(.socketStatusChanged(PhoneWifiManager.parseSocketStatus(packet.payload)))
        }
        wifiPacketRouter.register(command: .otaProgress) { [weak self] packet in self?.wifiOtaManager.handleOtaProgress(packet) }
        wifiPacketRouter.register(command: .otaEnd) { [weak self] packet in self?.wifiOtaManager.handleOtaEnd(packet) }
    }

    private func handleBleDisconnected(_ error: Error) {
        bleCommandExecutor.cancelAll(error)
        bleAudioManager.reset()
        bleAudioSyncManager.handleTransportDisconnected(error)
        flashIdeaManager.reset()
        fileMarkManager.reset()
        realTimeSync.reset()
    }
}
