import Foundation

public enum BRBluetoothState: String, Sendable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum BRConnectionState: String, Sendable {
    case idle
    case scanning
    case connecting
    case connected
    case disconnecting
    case disconnected
    case failed
}

public enum BRWifiState: String, Sendable {
    case unknown
    case disconnected
    case connecting
    case connectedToDeviceHotspot
    case socketConnecting
    case socketConnected
    case socketClosed
}

public enum BRSDKEvent: Sendable {
    case bluetoothStateChanged(BRBluetoothState)
    case deviceDiscovered(BRDiscoveredDevice)
    case deviceConnected(BRConnectedDevice)
    case deviceDisconnected(BRDisconnectInfo)
    case boundDeviceSaved(BRBoundDeviceInfo)
    case boundDeviceRemoved
    case wifiStateChanged(BRWifiState)
    case socketStatusChanged(BRSocketStatus)
    case recordStarted(BRRecordStartInfo)
    case recordStopped(BRRecordStopResult)
    case audioFrame(BRPacket)
    case fileSyncProgress(BRFileSyncProgress)
    case singleFileSyncFinished(BRSingleFinishResult)
    case realtimeSyncFinished(BRRealTimeSyncResult)
    case flashIdeaStarted(BRFlashIdeaStartResult)
    case flashIdeaData(BRFlashIdeaStartInfo, BRPacket)
    case flashIdeaEnded(BRFlashIdeaEndResult)
    case fileMarked(BRFileMarkResult)
    case otaProgress(BROtaProgress)
    case otaFinished(BROtaResult)
    case earphoneScanned(BREarphoneScanResult)
    case earphoneConnectionChanged(BREarphoneConnectionStatusResult)
}
