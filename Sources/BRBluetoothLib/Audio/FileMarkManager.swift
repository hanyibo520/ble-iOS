import Foundation

public final class FileMarkManager {
    private let context: BRSDKContext
    private let currentRecordProvider: () -> BRRecordStartInfo?

    init(context: BRSDKContext, currentRecordProvider: @escaping () -> BRRecordStartInfo?) {
        self.context = context
        self.currentRecordProvider = currentRecordProvider
    }

    func handleFileMark(_ packet: BRPacket) {
        if let mark = try? BRFileMarkResult.fromPayload(packet.payload) {
            context.emit(.fileMarked(mark))
        }
    }

    public func currentRecordForMark() -> BRRecordStartInfo? {
        currentRecordProvider()
    }

    func reset() {}
}
