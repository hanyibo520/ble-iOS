import Foundation

public final class BleAudioManager {
    private enum Phase { case idle, recording, paused, stopped(BRRecordStopResult) }
    private let lock = NSLock()
    private let executor: CommandExecutor
    private let context: BRSDKContext
    private let realTimeSync: RealTimeSync
    private var phase: Phase = .idle
    private var currentStartInfo: BRRecordStartInfo?

    init(executor: CommandExecutor, context: BRSDKContext, realTimeSync: RealTimeSync) {
        self.executor = executor
        self.context = context
        self.realTimeSync = realTimeSync
    }

    public func startRecording(startType: Int = 1) async throws -> BRRecordStartInfo {
        guard canStart else { throw BRSDKError.invalidState(message: "Recording is already active.") }
        let packet = try await executor.execute(.recordStart, timeout: context.configuration.bleCommandTimeout)
        let info = try BRRecordStartInfo.fromPayload(packet.payload)
        if let error = info.error { throw BRSDKError.deviceError(code: 0, message: error) }
        try realTimeSync.start(info)
        setRecording(info)
        context.emit(.recordStarted(info))
        return info
    }

    public func stopRecording(stopType: Int = 1) async throws -> BRRecordStopResult {
        guard canStop else { throw BRSDKError.invalidState(message: "Recording is not active.") }
        let packet = try await executor.execute(.recordStop, timeout: context.configuration.bleCommandTimeout)
        let result = await buildStopResult(payload: packet.payload, stopType: stopType)
        lock.br_withLock { phase = .stopped(result); currentStartInfo = nil }
        context.emit(.recordStopped(result))
        if let sync = result.realTimeSyncResult { context.emit(.realtimeSyncFinished(sync)) }
        return result
    }

    public func pauseRecording() async throws -> Bool {
        guard isRecording else { throw BRSDKError.invalidState(message: "Recording is not active.") }
        let packet = try await executor.execute(.recordPause, timeout: context.configuration.bleCommandTimeout)
        let success = try BRPayloadCodec.firstByte(packet.payload, name: "recordPause") == 0x01
        if success { lock.br_withLock { phase = .paused } }
        return success
    }

    public func resumeRecording() async throws -> Bool {
        guard isPaused else { throw BRSDKError.invalidState(message: "Recording is not paused.") }
        let packet = try await executor.execute(.recordResume, timeout: context.configuration.bleCommandTimeout)
        let success = try BRPayloadCodec.firstByte(packet.payload, name: "recordResume") == 0x01
        if success { lock.br_withLock { phase = .recording } }
        return success
    }

    public func getRecordStatus() -> BRRecordStatus {
        lock.br_withLock {
            switch phase {
            case .idle, .stopped:
                return BRRecordStatus(isRecording: false, currentFile: currentStartInfo?.file, rawStatus: 0)
            case .recording:
                return BRRecordStatus(isRecording: true, currentFile: currentStartInfo?.file, rawStatus: 1)
            case .paused:
                return BRRecordStatus(isRecording: true, currentFile: currentStartInfo?.file, rawStatus: 2)
            }
        }
    }

    func getCurrentRecordStartInfo() -> BRRecordStartInfo? {
        lock.br_withLock { currentStartInfo }
    }

    func handleDevicePushOnRecordStart(_ packet: BRPacket) {
        guard let info = try? BRRecordStartInfo.fromPayload(packet.payload) else { return }
        try? realTimeSync.start(info)
        setRecording(info)
        context.emit(.recordStarted(info))
    }

    func handleDevicePushOnRecordStop(_ packet: BRPacket) {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.buildStopResult(payload: packet.payload, stopType: 0)
            self.lock.br_withLock { self.phase = .stopped(result); self.currentStartInfo = nil }
            self.context.emit(.recordStopped(result))
        }
    }

    func handleRealtimeAudioPacket(_ packet: BRPacket) {
        context.emit(.audioFrame(packet))
        realTimeSync.onReceive(packet)
    }

    func reset() {
        lock.br_withLock {
            phase = .idle
            currentStartInfo = nil
        }
        realTimeSync.reset()
    }

    private var canStart: Bool {
        lock.br_withLock {
            if case .recording = phase { return false }
            if case .paused = phase { return false }
            return true
        }
    }

    private var canStop: Bool {
        lock.br_withLock {
            if case .recording = phase { return true }
            if case .paused = phase { return true }
            return false
        }
    }

    private var isRecording: Bool {
        lock.br_withLock { if case .recording = phase { return true }; return false }
    }

    private var isPaused: Bool {
        lock.br_withLock { if case .paused = phase { return true }; return false }
    }

    private func setRecording(_ info: BRRecordStartInfo) {
        lock.br_withLock {
            currentStartInfo = info
            phase = .recording
        }
    }

    private func buildStopResult(payload: Data, stopType: Int) async -> BRRecordStopResult {
        let crc = try? BRPayloadCodec.uint16LE(payload, name: "recordStopCRC")
        let info = getCurrentRecordStartInfo()
        var syncResult: BRRealTimeSyncResult?
        if let crc, crc != 0 {
            syncResult = try? await realTimeSync.finishOrNil(crc: crc)
        } else {
            realTimeSync.reset()
        }
        return BRRecordStopResult(startInfo: info, crc: crc, stopType: stopType, realTimeSyncResult: syncResult)
    }
}
