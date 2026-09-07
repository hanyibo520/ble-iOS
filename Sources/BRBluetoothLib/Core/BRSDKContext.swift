import Foundation

public struct BRSDKConfiguration: Equatable, Sendable {
    public var bleCommandTimeout: TimeInterval
    public var bleNotifyTimeout: TimeInterval
    public var wifiCommandTimeout: TimeInterval
    public var fileSyncTimeout: TimeInterval
    public var otaPacketTimeout: TimeInterval
    public var syncRootDirectory: URL?

    public init(
        bleCommandTimeout: TimeInterval = 5,
        bleNotifyTimeout: TimeInterval = 5,
        wifiCommandTimeout: TimeInterval = 8,
        fileSyncTimeout: TimeInterval = 60,
        otaPacketTimeout: TimeInterval = 8,
        syncRootDirectory: URL? = nil
    ) {
        self.bleCommandTimeout = bleCommandTimeout
        self.bleNotifyTimeout = bleNotifyTimeout
        self.wifiCommandTimeout = wifiCommandTimeout
        self.fileSyncTimeout = fileSyncTimeout
        self.otaPacketTimeout = otaPacketTimeout
        self.syncRootDirectory = syncRootDirectory
    }
}

final class BRSDKContext: @unchecked Sendable {
    private let lock = NSLock()
    private var configurationStorage: BRSDKConfiguration
    private weak var delegateStorage: BRSDKDelegate?
    private weak var loggerStorage: BRSDKLogger?

    init(configuration: BRSDKConfiguration = BRSDKConfiguration(), logger: BRSDKLogger? = nil) {
        self.configurationStorage = configuration
        self.loggerStorage = logger
    }

    var configuration: BRSDKConfiguration {
        lock.br_withLock { configurationStorage }
    }

    func updateConfiguration(_ configuration: BRSDKConfiguration) {
        lock.br_withLock { configurationStorage = configuration }
    }

    func updateDelegate(_ delegate: BRSDKDelegate?) {
        lock.br_withLock { delegateStorage = delegate }
    }

    func updateLogger(_ logger: BRSDKLogger?) {
        lock.br_withLock { loggerStorage = logger }
    }

    func emit(_ event: BRSDKEvent) {
        let delegate = lock.br_withLock { delegateStorage }
        DispatchQueue.main.async {
            delegate?.bluetoothSDKDidEmit(event: event)
        }
    }

    func log(_ level: BRSDKLogLevel, tag: String, _ message: String, error: Error? = nil) {
        let logger = lock.br_withLock { loggerStorage }
        logger?.bluetoothSDKLog(level: level, tag: tag, message: message, error: error)
    }
}
