import Foundation

public final class BleAudioSyncManager {
    private let executor: CommandExecutor
    private let context: BRSDKContext
    private let singleFileSynchro: SingleFileSynchro
    private let syncDirManager: SyncDirManager
    private var expectedFileCount: Int?
    private var receivedFiles: [BRAudioFileInfo] = []
    private var fileListContinuation: CheckedContinuation<[BRAudioFileInfo], Error>?
    private var finishContinuation: CheckedContinuation<UInt16, Error>?
    private let lock = NSLock()

    init(executor: CommandExecutor, context: BRSDKContext, singleFileSynchro: SingleFileSynchro, syncDirManager: SyncDirManager) {
        self.executor = executor
        self.context = context
        self.singleFileSynchro = singleFileSynchro
        self.syncDirManager = syncDirManager
    }

    public func enableBleSyncMode(_ enable: Bool) async throws -> Bool {
        let packet = try await executor.execute(.syncStateNotify, payload: Data([enable ? 1 : 0]), timeout: context.configuration.bleCommandTimeout)
        return packet.payload.first.map { $0 == (enable ? 1 : 0) } ?? true
    }

    public func fetchBleFileList() async throws -> [BRAudioFileInfo] {
        _ = try await enableBleSyncMode(true)
        defer { Task { _ = try? await enableBleSyncMode(false) } }
        return try await onlyFetchBleFileList()
    }

    public func onlyFetchBleFileList(timeout: TimeInterval? = nil) async throws -> [BRAudioFileInfo] {
        try beginFileListCollection()
        return try await waitForFileList(timeout: timeout ?? context.configuration.fileSyncTimeout) { [executor] in
            try await executor.sendWithoutResponse(.getFileList)
        }
    }

    public func startBleSyncOne(_ targetFile: BRAudioFileInfo, observer: FileSyncObserver? = nil) async throws -> BRSingleFinishResult {
        guard syncDirManager.shouldSync(targetFile) else {
            throw BRSDKError.invalidState(message: "File is already synced: \(targetFile.file).")
        }
        try singleFileSynchro.start(fileInfo: targetFile, observer: observer)
        do {
            let crc = try await waitForFinishCRC(timeout: context.configuration.fileSyncTimeout) { [executor] in
                try await executor.sendWithoutResponse(.syncFileData, payload: Data(targetFile.file.utf8))
            }
            return try await singleFileSynchro.finish(deviceFileCRC: crc)
        } catch {
            singleFileSynchro.cancelCurrent(reason: "BLE sync failed")
            throw error
        }
    }

    public func startBleSyncQueue(_ wantFiles: [BRAudioFileInfo], observer: FileSyncObserver? = nil) async throws -> [BRSingleFinishResult] {
        _ = try await enableBleSyncMode(true)
        defer { Task { _ = try? await enableBleSyncMode(false) } }
        var results: [BRSingleFinishResult] = []
        for file in wantFiles where syncDirManager.shouldSync(file) {
            results.append(try await startBleSyncOne(file, observer: observer))
        }
        return results
    }

    public func closeBleSyncQueue() async throws -> Bool {
        singleFileSynchro.cancelCurrent(reason: "close BLE sync")
        return try await enableBleSyncMode(false)
    }

    func handleFileListPacket(_ packet: BRPacket) {
        guard let json = try? BRPayloadCodec.decodeJSONObject(packet.payload) else { return }
        if BRPayloadCodec.string(json, "AudioFileList") == "MemoryBusy" {
            finishFileList(.failure(BRSDKError.deviceError(code: 1, message: "MemoryBusy")))
            return
        }
        if json["FileNum"] != nil {
            lock.br_withLock {
                expectedFileCount = BRPayloadCodec.int(json, "FileNum")
                receivedFiles.removeAll()
            }
            maybeFinishFileList()
            return
        }
        let file = BRAudioFileInfo.fromJSONObject(json)
        lock.br_withLock { receivedFiles.append(file) }
        maybeFinishFileList()
    }

    func handleSyncAudioData(_ packet: BRPacket) {
        singleFileSynchro.onReceive(packet)
    }

    func handleSyncStopCRC(_ packet: BRPacket) {
        let crc = try? BRPayloadCodec.uint16LE(packet.payload, name: "syncStopCRC")
        guard let crc else { return }
        finishSync(.success(crc))
    }

    func handleDeviceDeleteFile(_ packet: BRPacket) {
        guard packet.payload.first == 0x01 else { return }
        context.emit(.fileMarked(BRFileMarkResult(type: 1, time: 0)))
    }

    func reset() {
        singleFileSynchro.reset()
        lock.br_withLock {
            expectedFileCount = nil
            receivedFiles.removeAll()
            fileListContinuation?.resume(throwing: BRSDKError.invalidState(message: "BLE sync reset."))
            fileListContinuation = nil
            finishContinuation?.resume(throwing: BRSDKError.invalidState(message: "BLE sync reset."))
            finishContinuation = nil
        }
    }

    func handleTransportDisconnected(_ error: Error) {
        reset()
    }

    private func beginFileListCollection() throws {
        try lock.br_withLock {
            guard fileListContinuation == nil else {
                throw BRSDKError.invalidState(message: "File list collection is already running.")
            }
            expectedFileCount = nil
            receivedFiles.removeAll()
        }
    }

    private func waitForFileList(timeout: TimeInterval, afterRegistering send: @escaping @Sendable () async throws -> Void) async throws -> [BRAudioFileInfo] {
        do {
            return try await BRAsyncTimeout.run(seconds: timeout) { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    lock.br_withLock { fileListContinuation = continuation }
                    maybeFinishFileList()
                    Task {
                        do {
                            try await send()
                        } catch {
                            finishFileList(.failure(error))
                        }
                    }
                }
            }
        } catch {
            finishFileList(.failure(error))
            throw error
        }
    }

    private func maybeFinishFileList() {
        let result: [BRAudioFileInfo]? = lock.br_withLock { () -> [BRAudioFileInfo]? in
            guard let expectedFileCount = self.expectedFileCount, receivedFiles.count >= expectedFileCount else { return nil }
            let files = receivedFiles
            self.expectedFileCount = nil
            receivedFiles.removeAll()
            return files
        }
        if let result { finishFileList(.success(result)) }
    }

    private func finishFileList(_ result: Result<[BRAudioFileInfo], Error>) {
        let continuation = lock.br_withLock { () -> CheckedContinuation<[BRAudioFileInfo], Error>? in
            let continuation = fileListContinuation
            fileListContinuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func waitForFinishCRC(timeout: TimeInterval, afterRegistering send: @escaping @Sendable () async throws -> Void) async throws -> UInt16 {
        try beginFinishWait()
        do {
            return try await BRAsyncTimeout.run(seconds: timeout) { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    lock.br_withLock { finishContinuation = continuation }
                    Task {
                        do {
                            try await send()
                        } catch {
                            finishSync(.failure(error))
                        }
                    }
                }
            }
        } catch {
            finishSync(.failure(error))
            throw error
        }
    }

    private func beginFinishWait() throws {
        try lock.br_withLock {
            guard finishContinuation == nil else {
                throw BRSDKError.invalidState(message: "File sync finish is already waiting.")
            }
        }
    }

    private func finishSync(_ result: Result<UInt16, Error>) {
        let continuation = lock.br_withLock { () -> CheckedContinuation<UInt16, Error>? in
            let continuation = finishContinuation
            finishContinuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
