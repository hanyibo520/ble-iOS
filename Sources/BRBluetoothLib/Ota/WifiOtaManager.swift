import Foundation

public final class WifiOtaManager {
    private let lock = NSLock()
    private let executor: CommandExecutor
    private let context: BRSDKContext
    private var isRunning = false
    private var progressContinuation: CheckedContinuation<BROtaResult, Error>?
    private var progressHandler: ((BROtaProgress) -> Void)?

    init(executor: CommandExecutor, context: BRSDKContext) {
        self.executor = executor
        self.context = context
    }

    @available(*, deprecated, message: "协议 WiFi OTA 主流程需要同时提供 BLE/WiFi 两个 ufw 包；请优先使用 startOta(packageSet:).")
    public func startOta(packageInfo: BROtaPackageInfo, progressHandler: ((BROtaProgress) -> Void)? = nil) async throws -> BROtaResult {
        try WifiOtaDebugManager.validatePackageInfo(packageInfo)
        return try await startOta(packageSet: nil, singlePackage: packageInfo, progressHandler: progressHandler)
    }

    public func startOta(packageSet: BROtaPackageSetInfo, progressHandler: ((BROtaProgress) -> Void)? = nil) async throws -> BROtaResult {
        try WifiOtaDebugManager.validatePackageInfo(packageSet.blePackage)
        try WifiOtaDebugManager.validatePackageInfo(packageSet.wifiPackage)
        return try await startOta(packageSet: packageSet, singlePackage: nil, progressHandler: progressHandler)
    }

    public func cancelOta() async throws {
        guard lock.br_withLock({ isRunning }) else { return }
        let packet = try await executor.execute(.otaEnd, payload: Data([0]), timeout: context.configuration.otaPacketTimeout)
        let status = Int(packet.payload.first ?? 0)
        let result = BROtaResult(success: false, errorCode: status, errorMessage: status == 0 ? "手动停止成功" : "手动停止失败")
        finish(result)
    }

    func handleOtaProgress(_ packet: BRPacket) {
        guard packet.payload.count >= 2 else { return }
        let chip = BROtaChipType(rawValue: packet.payload[0])
        let value = packet.payload[1]
        let progress = BROtaProgress(stage: .writing, chipType: chip, currentPacket: Int(value), totalPacket: 100, progress: value == 0xFF ? 0 : Double(value) / 100)
        emitProgress(progress)
    }

    func handleOtaEnd(_ packet: BRPacket) {
        let success = packet.payload.first == 0x01
        finish(BROtaResult(success: success, errorCode: success ? 0 : 1, errorMessage: success ? nil : "OTA 结束失败"))
    }

    func reset() {
        lock.br_withLock {
            isRunning = false
            progressHandler = nil
            progressContinuation?.resume(throwing: BRSDKError.invalidState(message: "OTA reset."))
            progressContinuation = nil
        }
    }

    private func startOta(packageSet: BROtaPackageSetInfo?, singlePackage: BROtaPackageInfo?, progressHandler: ((BROtaProgress) -> Void)?) async throws -> BROtaResult {
        try lock.br_withLock {
            guard !isRunning else { throw BRSDKError.invalidState(message: "OTA is already running.") }
            isRunning = true
            self.progressHandler = progressHandler
        }
        do {
            let requiredMask = try await sendOtaStart(packageSet: packageSet, singlePackage: singlePackage)
            let packages = try resolveRequiredPackages(mask: requiredMask, packageSet: packageSet, singlePackage: singlePackage)
            for (index, package) in packages.enumerated() {
                let endStatus = try await transfer(package)
                let isLastPackage = index == packages.count - 1
                if isLastPackage {
                    guard endStatus == 0x00 else {
                        throw BRSDKError.deviceError(code: Int(endStatus), message: "OTA 数据包推送未全部完成")
                    }
                } else {
                    guard endStatus == 0x01 else {
                        throw BRSDKError.deviceError(code: Int(endStatus), message: "OTA 数据包推送结束状态异常")
                    }
                }
            }
            return try await waitForOtaEnd()
        } catch {
            reset()
            throw error
        }
    }

    private func sendOtaStart(packageSet: BROtaPackageSetInfo?, singlePackage: BROtaPackageInfo?) async throws -> UInt8 {
        let payload: Data
        if let packageSet {
            let bleSize = try fileSize(packageSet.blePackage.fileURL)
            let wifiSize = try fileSize(packageSet.wifiPackage.fileURL)
            payload = try BRPayloadCodec.encodeJSONObject([
                "BleFileSize": bleSize,
                "BleFileVerson": packageSet.blePackage.version,
                "BleFileVersonPatch": packageSet.blePackage.versionPatch,
                "WifiFileSize": wifiSize,
                "WifiFileVerson": packageSet.wifiPackage.version,
                "WifiFileVersonPatch": packageSet.wifiPackage.versionPatch
            ])
        } else if let singlePackage {
            let size = try fileSize(singlePackage.fileURL)
            if singlePackage.chipType == .ble {
                payload = try BRPayloadCodec.encodeJSONObject(["BleFileSize": size, "BleFileVerson": singlePackage.version, "BleFileVersonPatch": singlePackage.versionPatch])
            } else {
                payload = try BRPayloadCodec.encodeJSONObject(["WifiFileSize": size, "WifiFileVerson": singlePackage.version, "WifiFileVersonPatch": singlePackage.versionPatch])
            }
        } else {
            throw BRSDKError.invalidArgument(name: "package", message: "OTA package is missing.")
        }
        let response = try await executor.execute(.otaStart, payload: payload, timeout: context.configuration.wifiCommandTimeout)
        guard response.payload.count >= 2 else { throw BRSDKError.parseFailed(message: "OTA start response needs 2 bytes.") }
        guard response.payload[0] == 0x01 else {
            throw BRSDKError.deviceError(code: Int(response.payload[1]), message: "设备拒绝 OTA")
        }
        emitProgress(BROtaProgress(stage: .started))
        return response.payload[1]
    }

    private func resolveRequiredPackages(mask: UInt8, packageSet: BROtaPackageSetInfo?, singlePackage: BROtaPackageInfo?) throws -> [BROtaPackageInfo] {
        if let packageSet {
            var packages: [BROtaPackageInfo] = []
            if mask & BROtaChipType.ble.rawValue != 0 { packages.append(packageSet.blePackage) }
            if mask & BROtaChipType.wifi.rawValue != 0 { packages.append(packageSet.wifiPackage) }
            return packages
        }
        guard let singlePackage, mask & singlePackage.chipType.rawValue != 0 else {
            throw BRSDKError.deviceError(code: Int(mask), message: "当前固件无需升级或缺少设备要求的芯片包")
        }
        return [singlePackage]
    }

    private func transfer(_ package: BROtaPackageInfo) async throws -> UInt8 {
        let data = try Data(contentsOf: package.fileURL)
        let packets = try WifiOtaDebugManager.splitPackageData(data, packetSize: package.packetSize)
        let start = try await executor.execute(.otaPackageStart, payload: Data([package.chipType.rawValue]), timeout: context.configuration.otaPacketTimeout)
        guard start.payload.first == 0x01 else {
            throw BRSDKError.deviceError(code: Int(start.payload.first ?? 0), message: "OTA 数据包推送开始失败")
        }
        for (index, packet) in packets.enumerated() {
            let sequence = UInt16(index & 0xFFFF)
            let response = try await executor.execute(.otaPackageData, payload: packet, sequence: sequence, timeout: context.configuration.otaPacketTimeout)
            guard response.payload.first == 0x00 else {
                throw BRSDKError.deviceError(code: Int(response.payload.first ?? 0), message: "OTA 数据包接收失败")
            }
            emitProgress(BROtaProgress(stage: .packageData, chipType: package.chipType, currentPacket: index + 1, totalPacket: packets.count, progress: Double(index + 1) / Double(packets.count)))
        }
        let end = try await executor.execute(.otaPackageEnd, payload: Data([package.chipType.rawValue]), timeout: context.configuration.otaPacketTimeout)
        guard let endStatus = end.payload.first else {
            throw BRSDKError.parseFailed(message: "OTA 数据包推送结束缺少状态")
        }
        emitProgress(BROtaProgress(stage: .packageEnd, chipType: package.chipType, currentPacket: packets.count, totalPacket: packets.count, progress: 1))
        return endStatus
    }

    private func waitForOtaEnd() async throws -> BROtaResult {
        try await BRAsyncTimeout.run(seconds: 180) { [weak self] in
            try await withCheckedThrowingContinuation { continuation in
                self?.lock.br_withLock { self?.progressContinuation = continuation }
            }
        }
    }

    private func emitProgress(_ progress: BROtaProgress) {
        lock.br_withLock { progressHandler }?(progress)
        context.emit(.otaProgress(progress))
    }

    private func finish(_ result: BROtaResult) {
        let continuation = lock.br_withLock { () -> CheckedContinuation<BROtaResult, Error>? in
            isRunning = false
            let continuation = progressContinuation
            progressContinuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
        context.emit(.otaFinished(result))
    }

    private func fileSize(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}
