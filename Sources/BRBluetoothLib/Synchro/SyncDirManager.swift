import Foundation

final class SyncDirManager: @unchecked Sendable {
    private let context: BRSDKContext

    init(context: BRSDKContext) {
        self.context = context
    }

    var rootDirectory: URL {
        if let configured = context.configuration.syncRootDirectory {
            return configured
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("BRBluetoothLibSync", isDirectory: true)
    }

    func fileURL(for fileName: String, temporary: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let name = temporary ? "\(fileName).tmp" : fileName
        return rootDirectory.appendingPathComponent(name)
    }

    func shouldSync(_ file: BRAudioFileInfo) -> Bool {
        !FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent(file.file).path)
    }
}
