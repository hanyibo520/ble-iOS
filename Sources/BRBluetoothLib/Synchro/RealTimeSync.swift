import Foundation

final class RealTimeSync: @unchecked Sendable {
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.bairong.ble-ios.realtime-sync-io")
    private let context: BRSDKContext
    private let syncDirManager: SyncDirManager
    private var startInfo: BRRecordStartInfo?
    private var fileHandle: FileHandle?
    private var cumulativeCRC: UInt16 = 0xFFFF

    init(context: BRSDKContext, syncDirManager: SyncDirManager) {
        self.context = context
        self.syncDirManager = syncDirManager
    }

    func start(_ info: BRRecordStartInfo) throws {
        reset()
        let url = try syncDirManager.fileURL(for: info.file, temporary: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        lock.br_withLock {
            startInfo = info
            fileHandle = handle
            cumulativeCRC = 0xFFFF
        }
    }

    func onReceive(_ packet: BRPacket) {
        guard packet.isAudioFrame, !packet.payload.isEmpty else { return }
        let payload = packet.payload
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.lock.br_withLock {
                try? self.fileHandle?.write(contentsOf: payload)
                self.cumulativeCRC = (try? BRCRC16.update(current: self.cumulativeCRC, data: payload)) ?? self.cumulativeCRC
            }
        }
    }

    func finishOrNil(crc: UInt16) async throws -> BRRealTimeSyncResult? {
        let snapshot = try ioQueue.sync {
            try lock.br_withLock { () throws -> (BRRecordStartInfo, UInt16) in
                guard let startInfo else { throw BRSDKError.invalidState(message: "No realtime sync is active.") }
                try fileHandle?.close()
                fileHandle = nil
                return (startInfo, cumulativeCRC)
            }
        }
        let temp = try syncDirManager.fileURL(for: snapshot.0.file, temporary: true)
        let final = try syncDirManager.fileURL(for: snapshot.0.file)
        guard snapshot.1 == crc else {
            reset()
            throw BRSDKError.crcMismatch(local: snapshot.1, remote: crc)
        }
        if FileManager.default.fileExists(atPath: final.path) {
            try? FileManager.default.removeItem(at: final)
        }
        try FileManager.default.moveItem(at: temp, to: final)
        let result = BRRealTimeSyncResult(file: snapshot.0.file, localFile: final, success: true, crc: crc)
        reset(keepFile: true)
        return result
    }

    func reset(keepFile: Bool = false) {
        let temp = ioQueue.sync {
            lock.br_withLock { () -> URL? in
                try? fileHandle?.close()
                fileHandle = nil
                let url = try? startInfo.map { try syncDirManager.fileURL(for: $0.file, temporary: true) }
                startInfo = nil
                cumulativeCRC = 0xFFFF
                return url ?? nil
            }
        }
        if !keepFile, let temp {
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
