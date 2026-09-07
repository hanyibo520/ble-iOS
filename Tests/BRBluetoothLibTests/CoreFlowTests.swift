import XCTest
@testable import BRBluetoothLib

final class CoreFlowTests: XCTestCase {
    func testResponseMatcherMatchesWifiBySequenceBeforeCommandFallback() async throws {
        let matcher = ResponseMatcher(channel: .wifi)
        let wait = try matcher.register(for: BRCommandRequestKey(channel: .wifi, command: .otaPackageData, sequence: 7), timeout: 1)
        let task = Task {
            try await wait.value()
        }

        XCTAssertTrue(matcher.fulfill(BRPacket(frameKind: .command, command: .otaPackageData, sequence: 7, payload: Data([0]))))

        let packet = try await task.value
        XCTAssertEqual(packet.sequence, 7)
        XCTAssertEqual(packet.payload, Data([0]))
    }

    func testRouterDispatchesUnmatchedPush() {
        let router = InboundPacketRouter()
        var routed: BRPacket?
        router.register(command: .fileMark) { packet in
            routed = packet
        }

        let packet = BRPacket(frameKind: .command, command: .fileMark, payload: Data([1]))
        XCTAssertTrue(router.route(packet))
        XCTAssertEqual(routed, packet)
    }

    func testWifiTransportDropsBufferedDataAfterCRCFailure() throws {
        let context = BRSDKContext()
        let parser = BRProtocolParser()
        let transport = WifiTransport(context: context, parser: parser)
        var received: [BRPacket] = []
        transport.setReceiveHandler { received.append($0) }

        var badFrame = try parser.encodeWifiPacket(.syncFileData, payload: Data("bad".utf8), sequence: 1)
        badFrame[22] = badFrame[22] ^ 0xFF
        XCTAssertThrowsError(try transport.handleSocketData(badFrame))

        let goodFrame = try parser.encodeWifiPacket(.getBattery, payload: Data([80]), sequence: 2)
        XCTAssertNoThrow(try transport.handleSocketData(goodFrame))
        XCTAssertEqual(received.map(\.command), [.getBattery])
        XCTAssertEqual(received.first?.payload, Data([80]))
    }

    func testManagerExposesExpectedSubsystems() {
        let sdk = BrBluetoothManager.getInstance()
        XCTAssertNotNil(sdk.blueScanManager)
        XCTAssertNotNil(sdk.phoneBluetoothManager)
        XCTAssertNotNil(sdk.deviceNormalManager)
        XCTAssertNotNil(sdk.bleAudioManager)
        XCTAssertNotNil(sdk.bleAudioSyncManager)
        XCTAssertNotNil(sdk.phoneWifiManager)
        XCTAssertNotNil(sdk.wifiSyncManager)
        XCTAssertNotNil(sdk.wifiOtaManager)
        XCTAssertNotNil(sdk.flashIdeaManager)
        XCTAssertNotNil(sdk.fileMarkManager)
        XCTAssertNotNil(sdk.earphoneModeManager)
    }

    func testEarphoneModeStatusUsesBinaryByte() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .ble)
        let matcher = ResponseMatcher(channel: .ble)
        let router = InboundPacketRouter()
        var executor: CommandExecutor!
        executor = CommandExecutor(kind: .ble, transport: transport, parser: parser, matcher: matcher, router: router)
        let manager = EarphoneModeManager(executor: executor, context: BRSDKContext())
        var sentPayload = Data()

        transport.onWrite = { data in
            let request = try parser.decodeBlePacket(data)
            sentPayload = request.payload
            _ = executor.receive(BRPacket(frameKind: .command, command: .earphoneModeSet, payload: Data([0, 1, 2])))
        }

        let result = try await manager.setEarphoneMode(enabled: true, earphoneMac: "82E7B810BF83", phoneMac: "123456789ABC")

        XCTAssertTrue(result.commandAvailable)
        XCTAssertEqual(sentPayload.count, 25)
        XCTAssertEqual(sentPayload.first, 0x01)
        XCTAssertEqual(String(data: Data(sentPayload.dropFirst()), encoding: .utf8), "82E7B810BF83123456789ABC")
    }

    func testSocketStatusEmptyPayloadMeansConnected() {
        let status = PhoneWifiManager.parseSocketStatus(Data())

        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.rawStatus, 1)
    }

    func testHandshakeRejectsUnexpectedBoundDeviceUUID() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .ble)
        let matcher = ResponseMatcher(channel: .ble)
        let router = InboundPacketRouter()
        let executor = CommandExecutor(kind: .ble, transport: transport, parser: parser, matcher: matcher, router: router)
        let coordinator = BRBLEHandshakeCoordinator(executor: executor)
        let task = Task {
            try await coordinator.perform(appInfo: BRHandshakeAppInfo(uuid: "app-uuid"), expectedDeviceUUID: "expected-device-uuid", timeout: 1)
        }
        let greeting = try BRPayloadCodec.encodeJSONObject(["uuid": "other-device-uuid"])
        var payload = Data([0x00])
        payload.append(greeting)

        try await Task.sleep(nanoseconds: 1_000_000)
        _ = executor.receive(BRPacket(frameKind: .command, command: .handshake, payload: payload))

        do {
            _ = try await task.value
            XCTFail("Expected handshake UUID mismatch to fail.")
        } catch BRSDKError.deviceError(let code, let message) {
            XCTAssertEqual(code, 0x01)
            XCTAssertEqual(message, "设备 UUID 与本地绑定记录不一致")
        }
    }

    func testOpenSocketWaitsForSocketStatusPush() async throws {
        let parser = BRProtocolParser()
        let context = BRSDKContext(configuration: BRSDKConfiguration(wifiCommandTimeout: 1))
        let wifiTransport = WifiTransport(context: context, parser: parser)
        let wifiMatcher = ResponseMatcher(channel: .wifi)
        let wifiRouter = InboundPacketRouter()
        let wifiExecutor = CommandExecutor(kind: .wifi, transport: wifiTransport, parser: parser, matcher: wifiMatcher, router: wifiRouter)
        let bleTransport = TestCommandTransport(kind: .ble)
        let bleExecutor = CommandExecutor(kind: .ble, transport: bleTransport, parser: parser, matcher: ResponseMatcher(channel: .ble), router: InboundPacketRouter())
        let manager = PhoneWifiManager(executor: bleExecutor, wifiExecutor: wifiExecutor, context: context, wifiTransport: wifiTransport) { nil }
        wifiTransport.setReceiveHandler { packet in _ = wifiExecutor.receive(packet) }
        wifiTransport.setOpenHandlerForTesting {
            try wifiTransport.handleSocketData(try parser.encodeWifiPacket(.socketStatus))
        }

        try await manager.openSocket()
        await manager.closeSocket()
    }

    func testBleSyncCatchesImmediateFinishCRCResponse() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .ble)
        let matcher = ResponseMatcher(channel: .ble)
        let router = InboundPacketRouter()
        let context = BRSDKContext(configuration: BRSDKConfiguration(fileSyncTimeout: 1, syncRootDirectory: temporaryDirectory()))
        let syncDirManager = SyncDirManager(context: context)
        let singleFileSynchro = SingleFileSynchro(context: context, syncDirManager: syncDirManager)
        var executor: CommandExecutor!
        executor = CommandExecutor(kind: .ble, transport: transport, parser: parser, matcher: matcher, router: router)
        let manager = BleAudioSyncManager(executor: executor, context: context, singleFileSynchro: singleFileSynchro, syncDirManager: syncDirManager)
        let audio = Data("abc".utf8)
        let crc = try BRCRC16.compute(audio)
        defer { try? FileManager.default.removeItem(at: syncDirManager.rootDirectory) }
        router.register(command: .syncFileData) { packet in manager.handleSyncAudioData(packet) }
        router.register(command: .syncStopCRC) { packet in manager.handleSyncStopCRC(packet) }

        transport.onWrite = { data in
            let request = try parser.decodeBlePacket(data)
            guard request.command == .syncFileData else { return }
            _ = executor.receive(BRPacket(frameKind: .audio, command: .syncFileData, frameIndex: 0, payload: audio))
            _ = executor.receive(BRPacket(frameKind: .command, command: .syncStopCRC, payload: BRPayloadCodec.encodeUInt16LE(crc)))
        }

        let result = try await manager.startBleSyncOne(BRAudioFileInfo(file: "R20260101-000000.opus", size: Int64(audio.count)))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.crc, crc)
        XCTAssertEqual(try Data(contentsOf: result.localFile), audio)
    }

    func testWifiFileListCatchesImmediateResponse() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .wifi)
        let matcher = ResponseMatcher(channel: .wifi)
        let router = InboundPacketRouter()
        let context = BRSDKContext(configuration: BRSDKConfiguration(fileSyncTimeout: 1, syncRootDirectory: temporaryDirectory()))
        let syncDirManager = SyncDirManager(context: context)
        let singleFileSynchro = SingleFileSynchro(context: context, syncDirManager: syncDirManager)
        var executor: CommandExecutor!
        executor = CommandExecutor(kind: .wifi, transport: transport, parser: parser, matcher: matcher, router: router)
        let manager = WifiAudioSyncManager(executor: executor, context: context, singleFileSynchro: singleFileSynchro, syncDirManager: syncDirManager)
        router.register(command: .getFileList) { packet in manager.handleFileListPacket(packet) }

        transport.onWrite = { data in
            let request = try XCTUnwrap(parser.decodeWifiPackets(data).first)
            guard request.command == .getFileList else { return }
            let payload = Data(#"{"FileNum":1,"AudioFileArray":[{"file":"R20260101-000001.opus","size":3,"creat_time":1767225601,"duration_ms":20,"type":3,"index":1,"delete":0,"toggle_switch":0}]}"#.utf8)
            _ = executor.receive(BRPacket(frameKind: .command, command: .getFileList, sequence: request.sequence, payload: payload))
        }

        let files = try await manager.onlyFetchFileList(timeout: 1)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.file, "R20260101-000001.opus")
    }

    func testWifiCloseSyncQueueClosesWifiAfterLeavingSyncMode() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .wifi)
        let matcher = ResponseMatcher(channel: .wifi)
        let router = InboundPacketRouter()
        let context = BRSDKContext(configuration: BRSDKConfiguration(wifiCommandTimeout: 1, syncRootDirectory: temporaryDirectory()))
        let syncDirManager = SyncDirManager(context: context)
        let singleFileSynchro = SingleFileSynchro(context: context, syncDirManager: syncDirManager)
        var didCloseWifi = false
        var executor: CommandExecutor!
        executor = CommandExecutor(kind: .wifi, transport: transport, parser: parser, matcher: matcher, router: router)
        let manager = WifiAudioSyncManager(executor: executor, context: context, singleFileSynchro: singleFileSynchro, syncDirManager: syncDirManager) {
            didCloseWifi = true
        }

        transport.onWrite = { data in
            let request = try XCTUnwrap(parser.decodeWifiPackets(data).first)
            XCTAssertEqual(request.command, .syncStateNotify)
            XCTAssertEqual(request.payload, Data([0]))
            _ = executor.receive(BRPacket(frameKind: .command, command: request.command, sequence: request.sequence, payload: request.payload))
        }

        let closeResult = try await manager.closeSyncQueue()
        XCTAssertTrue(closeResult)
        XCTAssertTrue(didCloseWifi)
    }

    func testWifiOtaRejectsIncompleteFinalPackageEndStatus() async throws {
        let parser = BRProtocolParser()
        let transport = TestCommandTransport(kind: .wifi)
        let matcher = ResponseMatcher(channel: .wifi)
        let router = InboundPacketRouter()
        let context = BRSDKContext(configuration: BRSDKConfiguration(wifiCommandTimeout: 1, otaPacketTimeout: 1))
        var executor: CommandExecutor!
        executor = CommandExecutor(kind: .wifi, transport: transport, parser: parser, matcher: matcher, router: router)
        let manager = WifiOtaManager(executor: executor, context: context)
        let directory = temporaryDirectory()
        let blePackageURL = directory.appendingPathComponent("update_xxx_ble_v12.4_0FC1-454BEF39_20241119.ufw")
        let wifiPackageURL = directory.appendingPathComponent("update_xxx_wifi_v1.6_5CEA-52E35B42_20241119.ufw")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0xAA]).write(to: blePackageURL)
        try Data([0xBB]).write(to: wifiPackageURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        transport.onWrite = { data in
            let request = try XCTUnwrap(parser.decodeWifiPackets(data).first)
            switch request.command {
            case .otaStart:
                _ = executor.receive(BRPacket(frameKind: .command, command: request.command, sequence: request.sequence, payload: Data([0x01, 0x01])))
            case .otaPackageStart:
                _ = executor.receive(BRPacket(frameKind: .command, command: request.command, sequence: request.sequence, payload: Data([0x01])))
            case .otaPackageData:
                _ = executor.receive(BRPacket(frameKind: .command, command: request.command, sequence: request.sequence, payload: Data([0x00])))
            case .otaPackageEnd:
                _ = executor.receive(BRPacket(frameKind: .command, command: request.command, sequence: request.sequence, payload: Data([0x01])))
            default:
                XCTFail("Unexpected OTA command \(request.command.hexString)")
            }
        }

        do {
            let packageSet = BROtaPackageSetInfo(
                blePackage: BROtaPackageInfo(fileURL: blePackageURL, chipType: .ble),
                wifiPackage: BROtaPackageInfo(fileURL: wifiPackageURL, chipType: .wifi)
            )
            _ = try await manager.startOta(packageSet: packageSet)
            XCTFail("Expected final package end status 0x01 to fail.")
        } catch BRSDKError.deviceError(let code, let message) {
            XCTAssertEqual(code, 1)
            XCTAssertEqual(message, "OTA 数据包推送未全部完成")
        }
    }

    func testBoundDeviceStoreKeepsMultipleDevices() {
        let suiteName = "BRBoundDeviceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BRBoundDeviceStore(defaults: defaults)
        let first = BRBoundDeviceInfo(deviceName: "T240-A", deviceSN: "A", deviceUUID: "uuid-a", appUUID: "app-a", peripheralIdentifier: "peripheral-a")
        let second = BRBoundDeviceInfo(deviceName: "T240-B", deviceSN: "B", deviceUUID: "uuid-b", appUUID: "app-b", peripheralIdentifier: "peripheral-b")

        store.save(first)
        store.save(second)

        XCTAssertEqual(store.loadAll(), [first, second])
        XCTAssertEqual(store.loadLast(), second)

        store.removeLast()

        XCTAssertEqual(store.loadAll(), [first])
        XCTAssertEqual(store.loadLast(), first)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class TestCommandTransport: CommandTransport {
    let kind: BRTransportKind
    var state: BRTransportState = .ready
    var writes: [Data] = []
    var onWrite: ((Data) async throws -> Void)?

    init(kind: BRTransportKind) {
        self.kind = kind
    }

    func write(_ data: Data) async throws {
        writes.append(data)
        try await onWrite?(data)
    }
}
