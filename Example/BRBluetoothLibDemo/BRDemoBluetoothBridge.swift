import BRBluetoothLib
import CoreBluetooth
import Foundation

@MainActor
protocol BRDemoBluetoothBridgeDelegate: AnyObject {
    func bridgeDidUpdateState(_ state: CBManagerState)
    func bridgeDidDiscover(_ device: BRDemoPeripheral)
    func bridgeDidConnect(_ peripheral: CBPeripheral)
    func bridgeDidDisconnect(_ peripheral: CBPeripheral?, error: Error?)
    func bridgeDidFail(_ message: String)
}

struct BRDemoPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let sn: String?
    let rssi: Int
    let serviceUUIDs: [UUID]
    fileprivate let peripheral: CBPeripheral

    var displayTitle: String {
        let trimmedSN = sn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSN.isEmpty {
            return trimmedSN
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName == "Unknown" {
            return "未获取SN"
        }
        return trimmedName
    }

    var detailLine: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName == "Unknown" {
            return "名称：未获取"
        }
        return "名称：\(trimmedName)"
    }

    func with(sn: String?) -> BRDemoPeripheral {
        BRDemoPeripheral(id: id, name: name, sn: sn, rssi: rssi, serviceUUIDs: serviceUUIDs, peripheral: peripheral)
    }

    var sdkDevice: BRDiscoveredDevice {
        BRDiscoveredDevice(
            identifier: id.uuidString,
            name: name,
            sn: sn,
            rssi: rssi,
            serviceUUIDs: serviceUUIDs
        )
    }
}

final class BRDemoBluetoothBridge: NSObject, ObservableObject {
    weak var delegate: BRDemoBluetoothBridgeDelegate?

    private let manager = BrBluetoothManager.shared
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var notifyContinuation: CheckedContinuation<Void, Error>?
    private var activePeripheral: CBPeripheral?
    private var mainWriteCharacteristic: CBCharacteristic?
    private var mainNotifyCharacteristic: CBCharacteristic?
    private var flashIdeaWriteCharacteristic: CBCharacteristic?
    private var flashIdeaNotifyCharacteristic: CBCharacteristic?
    private var pendingScan = false

    func startScan() {
        _ = central
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unknown, .resetting:
            pendingScan = true
            notifyMain { $0.bridgeDidFail("蓝牙初始化中，稍后会自动开始扫描") }
        default:
            notifyMain { $0.bridgeDidFail("蓝牙不可用，当前状态：\(self.central.state.brDemoDescription)") }
        }
    }

    func connectLastBoundDevice() async throws -> BRDiscoveredDevice {
        _ = central
        guard central.state == .poweredOn else {
            throw BRSDKError.invalidState(message: "蓝牙不可用，当前状态：\(central.state.brDemoDescription)")
        }
        guard let boundDevice = manager.phoneBluetoothManager.getLastBoundDevice() else {
            throw BRSDKError.invalidState(message: "没有已绑定设备")
        }
        guard let identifier = UUID(uuidString: boundDevice.peripheralIdentifier) else {
            throw BRSDKError.invalidState(message: "已绑定设备缺少可回连的外设标识")
        }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            throw BRSDKError.invalidState(message: "系统没有找到已绑定外设，请先扫描并手动连接一次")
        }
        let device = BRDiscoveredDevice(
            identifier: boundDevice.peripheralIdentifier,
            name: boundDevice.deviceName,
            sn: boundDevice.deviceSN,
            serviceUUIDs: [BRGattUUIDs.mainService]
        )
        try await connectPeripheral(peripheral)
        return device
    }

    private func beginScan() {
        pendingScan = false
        central.scanForPeripherals(
            withServices: [
                CBUUID(nsuuid: BRGattUUIDs.advertisementService),
                CBUUID(nsuuid: BRGattUUIDs.mainService)
            ],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func resetPeripheralState() {
        mainWriteCharacteristic = nil
        mainNotifyCharacteristic = nil
        flashIdeaWriteCharacteristic = nil
        flashIdeaNotifyCharacteristic = nil
    }

    private func connectPeripheral(_ peripheral: CBPeripheral) async throws {
        if connectContinuation != nil {
            throw BRSDKError.invalidState(message: "已有 BLE 连接正在进行")
        }
        guard central.state == .poweredOn else {
            throw BRSDKError.invalidState(message: "蓝牙不可用，当前状态：\(central.state.brDemoDescription)")
        }
        stopScan()
        activePeripheral = peripheral
        resetPeripheralState()
        peripheral.delegate = self
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(peripheral)
        }
        manager.phoneBluetoothManager.bindTransport(dataWriter: self, notifyController: self)
    }

    private func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [UUID] {
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else {
            return []
        }
        return serviceUUIDs.compactMap(\.brDemoFoundationUUID)
    }

    private func notifyStateUnavailable(_ state: CBManagerState) {
        guard state != .poweredOn else { return }
        let message: String
        switch state {
        case .poweredOff:
            message = "蓝牙已关闭，请在系统里打开蓝牙"
        case .unauthorized:
            message = "没有蓝牙权限，请在设置里允许 demo 使用蓝牙"
        case .unsupported:
            message = "当前设备不支持 BLE"
        default:
            message = "蓝牙不可用，当前状态：\(state.brDemoDescription)"
        }
        notifyMain { $0.bridgeDidFail(message) }
    }

    func stopScan() {
        pendingScan = false
        central.stopScan()
    }

    func connect(_ device: BRDemoPeripheral) async throws {
        try await connectPeripheral(device.peripheral)
    }

    func disconnect() {
        manager.phoneBluetoothManager.unbindTransport()
        if let activePeripheral {
            central.cancelPeripheralConnection(activePeripheral)
        }
        activePeripheral = nil
        resetPeripheralState()
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        let continuation = connectContinuation
        connectContinuation = nil
        continuation?.resume(with: result)
    }

    private func finishNotify(_ result: Result<Void, Error>) {
        let continuation = notifyContinuation
        notifyContinuation = nil
        continuation?.resume(with: result)
    }

    private func notifyMain(_ body: @escaping @MainActor (BRDemoBluetoothBridgeDelegate) -> Void) {
        guard let delegate else { return }
        Task { @MainActor in
            body(delegate)
        }
    }
}

extension BRDemoBluetoothBridge: BRBLEDataWriting {
    func write(_ data: Data) throws {
        let isFlashIdeaCommand = data.brDemoCommandCode == .flashIdeaStart
            || data.brDemoCommandCode == .flashIdeaData
            || data.brDemoCommandCode == .flashIdeaStop
        guard let peripheral = activePeripheral,
              let characteristic = isFlashIdeaCommand ? flashIdeaWriteCharacteristic : mainWriteCharacteristic
        else {
            throw BRSDKError.transportUnavailable(kind: .ble)
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
}

extension BRDemoBluetoothBridge: BRBLENotifyControlling {
    func setNotifyEnabled(_ enabled: Bool, timeout: TimeInterval) async throws {
        guard let peripheral = activePeripheral,
              let mainNotifyCharacteristic else {
            throw BRSDKError.transportUnavailable(kind: .ble)
        }
        if let flashIdeaNotifyCharacteristic {
            peripheral.setNotifyValue(enabled, for: flashIdeaNotifyCharacteristic)
        }
        try await withCheckedThrowingContinuation { continuation in
            notifyContinuation = continuation
            peripheral.setNotifyValue(enabled, for: mainNotifyCharacteristic)
        }
    }
}

extension BRDemoBluetoothBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        notifyMain { $0.bridgeDidUpdateState(central.state) }
        if central.state == .poweredOn, pendingScan {
            beginScan()
            return
        }
        if central.state != .poweredOn {
            notifyStateUnavailable(central.state)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let device = BRDemoPeripheral(
            id: peripheral.identifier,
            name: name,
            sn: nil,
            rssi: RSSI.intValue,
            serviceUUIDs: advertisedServiceUUIDs(from: advertisementData),
            peripheral: peripheral
        )
        notifyMain { $0.bridgeDidDiscover(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        notifyMain { $0.bridgeDidConnect(peripheral) }
        peripheral.discoverServices([CBUUID(nsuuid: BRGattUUIDs.mainService), CBUUID(nsuuid: BRGattUUIDs.flashIdeaService)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishConnect(.failure(error ?? BRSDKError.invalidState(message: "BLE 连接失败")))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        notifyMain { $0.bridgeDidDisconnect(peripheral, error: error) }
    }
}

extension BRDemoBluetoothBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            finishConnect(.failure(error))
            return
        }
        guard let services = peripheral.services,
              services.contains(where: { $0.uuid == CBUUID(nsuuid: BRGattUUIDs.mainService) })
        else {
            finishConnect(.failure(BRSDKError.invalidState(message: "未发现目标 BLE 服务，请确认选择的是录音卡设备")))
            return
        }
        services.forEach { service in
            let uuids: [CBUUID]
            if service.uuid == CBUUID(nsuuid: BRGattUUIDs.flashIdeaService) {
                uuids = [CBUUID(nsuuid: BRGattUUIDs.flashIdeaWrite), CBUUID(nsuuid: BRGattUUIDs.flashIdeaNotify)]
            } else {
                uuids = [CBUUID(nsuuid: BRGattUUIDs.mainWrite), CBUUID(nsuuid: BRGattUUIDs.mainNotify)]
            }
            peripheral.discoverCharacteristics(uuids, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            finishConnect(.failure(error))
            return
        }
        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case CBUUID(nsuuid: BRGattUUIDs.mainWrite):
                mainWriteCharacteristic = characteristic
            case CBUUID(nsuuid: BRGattUUIDs.mainNotify):
                mainNotifyCharacteristic = characteristic
            case CBUUID(nsuuid: BRGattUUIDs.flashIdeaWrite):
                flashIdeaWriteCharacteristic = characteristic
            case CBUUID(nsuuid: BRGattUUIDs.flashIdeaNotify):
                flashIdeaNotifyCharacteristic = characteristic
            default:
                break
            }
        }
        if mainWriteCharacteristic != nil, mainNotifyCharacteristic != nil {
            finishConnect(.success(()))
        } else if service.uuid == CBUUID(nsuuid: BRGattUUIDs.mainService) {
            finishConnect(.failure(BRSDKError.invalidState(message: "未发现目标 BLE 特征，请确认设备固件服务 UUID 是否匹配")))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(nsuuid: BRGattUUIDs.mainNotify) else { return }
        if let error {
            finishNotify(.failure(error))
        } else {
            finishNotify(.success(()))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            notifyMain { $0.bridgeDidFail(error.localizedDescription) }
            return
        }
        guard let data = characteristic.value else { return }
        do {
            if characteristic.uuid == CBUUID(nsuuid: BRGattUUIDs.flashIdeaNotify) {
                try manager.phoneBluetoothManager.receiveFlashIdeaNotifyData(data)
            } else {
                try manager.phoneBluetoothManager.receiveMainNotifyData(data)
            }
        } catch {
            notifyMain { $0.bridgeDidFail(error.localizedDescription) }
        }
    }
}

private extension Data {
    var brDemoCommandCode: BRCommandCode? {
        guard count >= 3 else { return nil }
        return BRCommandCode(rawValue: (UInt16(self[1]) << 8) | UInt16(self[2]))
    }
}

private extension CBUUID {
    var brDemoFoundationUUID: UUID? {
        UUID(uuidString: uuidString)
    }
}

private extension CBManagerState {
    var brDemoDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}
