import Foundation

public final class FlashIdeaManager {
    private let lock = NSLock()
    private let context: BRSDKContext
    private let realTimeSync: RealTimeSync
    private var statusStorage: BRFlashIdeaStatus = .idle
    private var currentInfo: BRFlashIdeaStartInfo?

    init(context: BRSDKContext, realTimeSync: RealTimeSync) {
        self.context = context
        self.realTimeSync = realTimeSync
    }

    public func getFlashIdeaStatus() -> BRFlashIdeaStatus {
        lock.br_withLock { statusStorage }
    }

    func handleFlashIdeaStart(_ packet: BRPacket) {
        guard let info = try? BRFlashIdeaStartInfo.fromPayload(packet.payload) else { return }
        if let error = info.error {
            let result = BRFlashIdeaStartResult(errorCode: 402, errorMessage: error)
            lock.br_withLock { statusStorage = .error(error); currentInfo = nil }
            context.emit(.flashIdeaStarted(result))
            return
        }
        try? realTimeSync.start(info.toRecordStartInfo())
        lock.br_withLock { statusStorage = .start(info); currentInfo = info }
        context.emit(.flashIdeaStarted(BRFlashIdeaStartResult(startInfo: info)))
    }

    func handleFlashIdeaData(_ packet: BRPacket) {
        guard packet.isAudioFrame, let info = lock.br_withLock({ currentInfo }) else { return }
        context.emit(.flashIdeaData(info, packet))
        realTimeSync.onReceive(packet)
    }

    func handleFlashIdeaStop(_ packet: BRPacket) {
        let info = lock.br_withLock { currentInfo }
        let crc = try? BRPayloadCodec.uint16LE(packet.payload, name: "flashIdeaStopCRC")
        Task { [weak self] in
            guard let self else { return }
            let sync: BRRealTimeSyncResult?
            if let crc {
                sync = try? await self.realTimeSync.finishOrNil(crc: crc)
            } else {
                sync = nil
            }
            let result = BRFlashIdeaEndResult(info: info, crc: crc, errorCode: crc == nil ? 400 : 0, errorMessage: crc == nil ? "闪念结束 CRC 缺失" : nil, realTimeSyncResult: sync)
            self.lock.br_withLock { self.statusStorage = .stop(result); self.currentInfo = nil }
            self.context.emit(.flashIdeaEnded(result))
        }
    }

    func reset() {
        lock.br_withLock {
            statusStorage = .idle
            currentInfo = nil
        }
        realTimeSync.reset()
    }
}
