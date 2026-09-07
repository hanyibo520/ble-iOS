import Foundation

public final class WifiAudioSyncManager {
    private let executor: CommandExecutor
    private let context: BRSDKContext
    private let singleFileSynchro: SingleFileSynchro
    private let syncDirManager: SyncDirManager
    private var fileListContinuation: CheckedContinuation<[BRAudioFileInfo], Error>?
    private var finishContinuation: CheckedContinuation<UInt16, Error>?
    private let lock = NSLock()

    init(executor: CommandExecutor, context: BRSDKContext, singleFileSynchro: SingleFileSynchro, syncDirManager: SyncDirManager) {
        self.executor = executor
        self.context = context
        self.singleFileSynchro = singleFileSynchro
        self.syncDirManager = syncDirManager
    }

    public func enableSyncMode(_ enable: Bool) async throws -> Bool {
        let packet = try await executor.execute(.syncStateNotify, payload: Data([enable ? 1 : 0]), timeout: context.configuration.wifiCommandTimeout)
        return packet.payload.first.map { $0 == (enable ? 1 : 0) } ?? true
    }

    public func fetchFileList(timeout: TimeInterval? = nil) async throws -> [BRAudioFileInfo] {
        _ = try await enableSyncMode(true)
        defer { Task { _ = try? await enableSyncMode(false) } }
        return try await onlyFetchFileList(timeout: timeout)
    }

    public func onlyFetchFileList(timeout: TimeInterval? = nil) async throws -> [BRAudioFileInfo] {
        try beginFileListWait()
        return try await waitForFileList(timeout: timeout ?? context.configuration.fileSyncTimeout) { [executor] in
            try await executor.sendWithoutResponse(.getFileList)
        }
    }

    public func startSyncOne(_ targetFile: BRAudioFileInfo, observer: FileSyncObserver? = nil) async throws -> BRSingleFinishResult {
        try singleFileSynchro.start(fileInfo: targetFile, observer: observer)
        do {
            let crc = try await waitForFinishCRC(timeout: context.configuration.fileSyncTimeout) { [executor] in
                try await executor.sendWithoutResponse(.syncFileData, payload: Data(targetFile.file.utf8))
            }
            return try await singleFileSynchro.finish(deviceFileCRC: crc)
        } catch {
            singleFileSynchro.cancelCurrent(reason: "WiFi sync failed")
            throw error
        }
    }

    public func startResumeSync(fileInfo: BRAudioFileInfo, resumeInfo: BRWifiResumeInfo, observer: FileSyncObserver? = nil) async throws -> BRSingleFinishResult {
        let payload = try BRPayloadCodec.encodeJSONObject(["file": resumeInfo.fileName, "index": resumeInfo.index, "crc": Int(resumeInfo.crc)])
        try singleFileSynchro.start(fileInfo: fileInfo, observer: observer, resumeInfo: resumeInfo)
        do {
            let crc = try await waitForFinishCRC(timeout: context.configuration.fileSyncTimeout) { [executor, context] in
                let response = try await executor.execute(.wifiResumeSync, payload: payload, timeout: context.configuration.wifiCommandTimeout)
                guard response.payload.first == 0x01 else {
                    throw BRSDKError.deviceError(code: Int(response.payload.first ?? 0), message: "断点续传失败")
                }
            }
            return try await singleFileSynchro.finish(deviceFileCRC: crc)
        } catch {
            singleFileSynchro.cancelCurrent(reason: "WiFi resume sync failed")
            throw error
        }
    }

    public func startSyncQueue(_ wantFiles: [BRAudioFileInfo], observer: FileSyncObserver? = nil) async throws -> [BRSingleFinishResult] {
        _ = try await enableSyncMode(true)
        defer { Task { _ = try? await enableSyncMode(false) } }
        var results: [BRSingleFinishResult] = []
        for file in wantFiles where syncDirManager.shouldSync(file) {
            results.append(try await startSyncOne(file, observer: observer))
        }
        return results
    }

    public func closeSyncQueue() async throws -> Bool {
        singleFileSynchro.cancelCurrent(reason: "close WiFi sync")
        return try await enableSyncMode(false)
    }

    func handleFileListPacket(_ packet: BRPacket) {
        if let list = try? BRAudioFileList.fromWifiPayload(packet.payload) {
            lock.br_withLock {
                fileListContinuation?.resume(returning: list.files)
                fileListContinuation = nil
            }
        }
    }

    func handleWifiFilePacket(_ packet: BRPacket) {
        singleFileSynchro.onReceive(packet)
    }

    func handleSyncStopCRC(_ packet: BRPacket) {
        guard let crc = try? BRPayloadCodec.uint16LE(packet.payload, name: "syncStopCRC") else { return }
        finishSync(.success(crc))
    }

    func reset() {
        singleFileSynchro.reset()
        lock.br_withLock {
            fileListContinuation?.resume(throwing: BRSDKError.invalidState(message: "WiFi sync reset."))
            fileListContinuation = nil
            finishContinuation?.resume(throwing: BRSDKError.invalidState(message: "WiFi sync reset."))
            finishContinuation = nil
        }
    }

    func handleTransportDisconnected(_ error: Error) {
        reset()
    }

    private func beginFileListWait() throws {
        try lock.br_withLock {
            guard fileListContinuation == nil else {
                throw BRSDKError.invalidState(message: "WiFi file list collection is already running.")
            }
        }
    }

    private func waitForFileList(timeout: TimeInterval, afterRegistering send: @escaping @Sendable () async throws -> Void) async throws -> [BRAudioFileInfo] {
        do {
            return try await BRAsyncTimeout.run(seconds: timeout) { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    lock.br_withLock { fileListContinuation = continuation }
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

    private func finishFileList(_ result: Result<[BRAudioFileInfo], Error>) {
        let continuation = lock.br_withLock { () -> CheckedContinuation<[BRAudioFileInfo], Error>? in
            let continuation = fileListContinuation
            fileListContinuation = nil
            return continuation
        }
        continuation?.resume(with: result)
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
