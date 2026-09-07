import Foundation

final class SingleFileSynchro: @unchecked Sendable {
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.bairong.ble-ios.single-file-sync-io")
    private let context: BRSDKContext
    private let syncDirManager: SyncDirManager
    private var fileInfo: BRAudioFileInfo?
    private var fileHandle: FileHandle?
    private var cumulativeCRC: UInt16 = 0xFFFF
    private var receivedBytes: Int64 = 0
    private var lastFrameIndex: Int = -1
    private var observer: FileSyncObserver?

    init(context: BRSDKContext, syncDirManager: SyncDirManager) {
        self.context = context
        self.syncDirManager = syncDirManager
    }

    var isSyncing: Bool {
        lock.br_withLock { fileInfo != nil }
    }

    func start(fileInfo: BRAudioFileInfo, observer: FileSyncObserver? = nil, resumeInfo: BRWifiResumeInfo? = nil) throws {
        cancelCurrent(reason: "replace sync")
        let temp = try syncDirManager.fileURL(for: fileInfo.file, temporary: true)
        if resumeInfo == nil {
            FileManager.default.createFile(atPath: temp.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: temp)
        try handle.seekToEnd()
        lock.br_withLock {
            self.fileInfo = fileInfo
            self.fileHandle = handle
            self.cumulativeCRC = resumeInfo?.crc ?? 0xFFFF
            self.receivedBytes = Int64((try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? NSNumber)?.intValue ?? 0)
            self.lastFrameIndex = resumeInfo?.index ?? -1
            self.observer = observer
        }
    }

    func onReceive(_ packet: BRPacket) {
        guard packet.isAudioFrame, !packet.payload.isEmpty else { return }
        let payload = packet.payload
        let frameIndex = packet.frameIndex
        let sequence = packet.sequence
        ioQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.lock.br_withLock { () -> (BRFileSyncProgress, FileSyncObserver?)? in
                guard let fileInfo = self.fileInfo, let fileHandle = self.fileHandle else { return nil }
                try? fileHandle.write(contentsOf: payload)
                self.cumulativeCRC = (try? BRCRC16.update(current: self.cumulativeCRC, data: payload)) ?? self.cumulativeCRC
                self.receivedBytes += Int64(payload.count)
                self.lastFrameIndex = Int(frameIndex ?? UInt32(sequence ?? 0))
                return (BRFileSyncProgress(file: fileInfo.file, receivedBytes: self.receivedBytes, totalBytes: fileInfo.size, lastFrameIndex: self.lastFrameIndex), self.observer)
            }
            if let snapshot {
                DispatchQueue.main.async {
                    snapshot.1?.onFileSyncProgress(snapshot.0)
                }
                self.context.emit(.fileSyncProgress(snapshot.0))
            }
        }
    }

    func finish(deviceFileCRC: UInt16) async throws -> BRSingleFinishResult {
        let snapshot = try ioQueue.sync {
            try lock.br_withLock { () throws -> (BRAudioFileInfo, UInt16) in
                guard let fileInfo else { throw BRSDKError.invalidState(message: "No file sync is active.") }
                try fileHandle?.close()
                fileHandle = nil
                return (fileInfo, cumulativeCRC)
            }
        }
        let temp = try syncDirManager.fileURL(for: snapshot.0.file, temporary: true)
        let final = try syncDirManager.fileURL(for: snapshot.0.file)
        guard snapshot.1 == deviceFileCRC else {
            cancelCurrent(reason: "crc mismatch")
            throw BRSDKError.crcMismatch(local: snapshot.1, remote: deviceFileCRC)
        }
        if FileManager.default.fileExists(atPath: final.path) {
            try FileManager.default.removeItem(at: final)
        }
        try FileManager.default.moveItem(at: temp, to: final)
        let result = BRSingleFinishResult(fileInfo: snapshot.0, localFile: final, success: true, crc: deviceFileCRC)
        reset(keepFile: true)
        context.emit(.singleFileSyncFinished(result))
        return result
    }

    func cancelCurrent(reason: String) {
        reset()
    }

    func reset(keepFile: Bool = false) {
        let temp = ioQueue.sync {
            lock.br_withLock { () -> URL? in
                try? fileHandle?.close()
                fileHandle = nil
                let url = try? fileInfo.map { try syncDirManager.fileURL(for: $0.file, temporary: true) }
                fileInfo = nil
                cumulativeCRC = 0xFFFF
                receivedBytes = 0
                lastFrameIndex = -1
                observer = nil
                return url ?? nil
            }
        }
        if !keepFile, let temp {
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
