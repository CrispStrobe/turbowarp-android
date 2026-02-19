import CoreBluetooth

// MARK: - CBCentralManager delegate proxy

/// Forwards CBCentralManagerDelegate calls to a SwiftCBCentralManagerDelegate without requiring NSObject.
class CBCentralManagerDelegateHelper: NSObject, CBCentralManagerDelegate {
    weak var delegate: SwiftCBCentralManagerDelegate?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.centralManagerDidUpdateState(central)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        delegate?.centralManager?(central, willRestoreState: dict)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        delegate?.centralManager?(central, didDiscover: peripheral,
                                  advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegate?.centralManager?(central, didConnect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.centralManager?(central, didFailToConnect: peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegate?.centralManager?(central, didDisconnectPeripheral: peripheral, error: error)
    }
}

@objc protocol SwiftCBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    @objc optional func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    @objc optional func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                       advertisementData: [String: Any], rssi RSSI: NSNumber)
    @objc optional func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    @objc optional func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                       error: Error?)
    @objc optional func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                       error: Error?)
}

// MARK: - CBPeripheral delegate proxy

/// Forwards CBPeripheralDelegate calls to a SwiftCBPeripheralDelegate without requiring NSObject.
class CBPeripheralDelegateHelper: NSObject, CBPeripheralDelegate {
    weak var delegate: SwiftCBPeripheralDelegate?

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        delegate?.peripheralDidUpdateName?(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        delegate?.peripheral?(peripheral, didModifyServices: invalidatedServices)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        delegate?.peripheral?(peripheral, didReadRSSI: RSSI, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegate?.peripheral?(peripheral, didDiscoverServices: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        delegate?.peripheral?(peripheral, didDiscoverIncludedServicesFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegate?.peripheral?(peripheral, didDiscoverCharacteristicsFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral?(peripheral, didUpdateValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral?(peripheral, didWriteValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral?(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral?(peripheral, didDiscoverDescriptorsFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        delegate?.peripheral?(peripheral, didUpdateValueForDescriptor: descriptor, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        delegate?.peripheral?(peripheral, didWriteValueForDescriptor: descriptor, error: error)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        delegate?.peripheralIsReady?(toSendWriteWithoutResponse: peripheral)
    }
}

@objc protocol SwiftCBPeripheralDelegate {
    @objc optional func peripheralDidUpdateName(_ peripheral: CBPeripheral)
    @objc optional func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    @objc optional func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didDiscoverIncludedServicesFor service: CBService, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didDiscoverCharacteristicsFor service: CBService, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didUpdateValueForDescriptor descriptor: CBDescriptor, error: Error?)
    @objc optional func peripheral(_ peripheral: CBPeripheral,
                                    didWriteValueForDescriptor descriptor: CBDescriptor, error: Error?)
    @objc optional func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
}
