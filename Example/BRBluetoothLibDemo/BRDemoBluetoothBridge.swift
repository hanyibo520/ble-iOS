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
    let rssi: Int
    fileprivate let peripheral: CBPeripheral

    var sdkDevice: BRDiscoveredDevice {
        BRDiscoveredDevice(
            identifier: id.uuidString,
            name: name,
            rssi: rssi,
            serviceUUIDs: [BRGattUUIDs.advertisementService, BRGattUUIDs.mainService]
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

    func startScan() {
        _ = central
        guard central.state == .poweredOn else {
            notifyMain { $0.bridgeDidFail("蓝牙未开启，当前状态：\(self.central.state.rawValue)") }
            return
        }
        central.scanForPeripherals(
            withServices: [CBUUID(nsuuid: BRGattUUIDs.advertisementService)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(_ device: BRDemoPeripheral) async throws {
        stopScan()
        activePeripheral = device.peripheral
        device.peripheral.delegate = self
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(device.peripheral)
        }
        manager.phoneBluetoothManager.bindTransport(dataWriter: self, notifyController: self)
    }

    func disconnect() {
        manager.phoneBluetoothManager.unbindTransport()
        if let activePeripheral {
            central.cancelPeripheralConnection(activePeripheral)
        }
        activePeripheral = nil
        mainWriteCharacteristic = nil
        mainNotifyCharacteristic = nil
        flashIdeaWriteCharacteristic = nil
        flashIdeaNotifyCharacteristic = nil
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
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let device = BRDemoPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
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
        peripheral.services?.forEach { service in
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
