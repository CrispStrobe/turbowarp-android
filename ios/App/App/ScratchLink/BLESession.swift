import CoreBluetooth
import Foundation

class BLESession: ScratchLinkSession, SwiftCBCentralManagerDelegate, SwiftCBPeripheralDelegate {
    private static let MinimumSignalStrength = -70

    private let central: CBCentralManager
    private let centralDelegateHelper: CBCentralManagerDelegateHelper
    private let peripheralDelegateHelper: CBPeripheralDelegateHelper

    private var filters: [BLEScanFilter]?
    private var optionalServices: Set<CBUUID>?
    private var reportedPeripherals: [CBUUID: CBPeripheral]?
    private var allowedServices: Set<CBUUID>?

    private var connectedPeripheral: CBPeripheral?
    private var connectionCompletion: JSONRPCCompletionHandler?

    typealias DelegateHandler = (Error?) -> Void
    private var characteristicDiscoveryCompletion: [CBUUID: [DelegateHandler]] = [:]
    private var valueUpdateHandlers: [CBCharacteristic: [DelegateHandler]] = [:]
    private var watchedCharacteristics: Set<CBCharacteristic> = []
    private var onBluetoothReadyTasks: [(JSONRPCError?) -> Void] = []

    private enum BluetoothState {
        case unavailable, available, unknown
    }

    private var currentState: BluetoothState {
        switch central.state {
        case .unsupported, .unauthorized, .poweredOff: return .unavailable
        case .poweredOn: return .available
        default: return .unknown
        }
    }

    required init(withSocket webSocket: ScratchWebSocket) throws {
        self.central = CBCentralManager()
        self.centralDelegateHelper = CBCentralManagerDelegateHelper()
        self.peripheralDelegateHelper = CBPeripheralDelegateHelper()
        try super.init(withSocket: webSocket)
        self.centralDelegateHelper.delegate = self
        self.central.delegate = self.centralDelegateHelper
        self.peripheralDelegateHelper.delegate = self
    }

    // MARK: - CBCentralManager state

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let btState = self.currentState
        if btState == .unknown { return }

        let error = (btState == .unavailable) ?
            JSONRPCError.applicationError(data: "Bluetooth unavailable: \(central.state)") : nil

        while let task = onBluetoothReadyTasks.popLast() {
            task(error)
        }

        if let peripheral = self.connectedPeripheral {
            if btState != .available {
                central.cancelPeripheralConnection(peripheral)
                self.connectedPeripheral = nil
                try? self.sendErrorNotification(
                    JSONRPCError.applicationError(data: "Bluetooth became unavailable"))
                self.sessionWasClosed()
            } else if peripheral.state != .connecting && peripheral.state != .connected {
                central.cancelPeripheralConnection(peripheral)
                self.connectedPeripheral = nil
                try? self.sendErrorNotification(
                    JSONRPCError.applicationError(data: "Peripheral disconnected"))
                self.sessionWasClosed()
            }
        }
    }

    // MARK: - discover

    func discover(withParams params: [String: Any], completion: @escaping JSONRPCCompletionHandler) throws {
        guard let jsonFilters = params["filters"] as? [[String: Any]] else {
            throw JSONRPCError.invalidParams(data: "could not parse filters in discovery request")
        }
        if jsonFilters.count < 1 {
            throw JSONRPCError.invalidParams(data: "discovery request must include filters")
        }

        let newFilters = try jsonFilters.map({ try BLEScanFilter(fromJSON: $0) })
        if newFilters.contains(where: { $0.isEmpty }) {
            throw JSONRPCError.invalidParams(data: "discovery request includes empty filter")
        }

        let newOptionalServices: Set<CBUUID>?
        if let jsonOptionalServices = params["optionalServices"] as? [String] {
            newOptionalServices = Set<CBUUID>(try jsonOptionalServices.compactMap({
                guard let uuid = GATTHelpers.getUUID(forService: $0) else {
                    throw JSONRPCError.invalidParams(data: "could not resolve UUID for optional service \($0)")
                }
                return uuid
            }))
        } else {
            newOptionalServices = nil
        }

        var newAllowedServices = Set<CBUUID>(newOptionalServices ?? [])
        for filter in newFilters {
            if let filterServices = filter.requiredServices {
                newAllowedServices.formUnion(filterServices)
            }
        }

        func doDiscover(error: JSONRPCError?) {
            if let error = error {
                completion(nil, error)
            } else {
                connectedPeripheral = nil
                filters = newFilters
                optionalServices = newOptionalServices
                allowedServices = newAllowedServices
                reportedPeripherals = [:]
                central.scanForPeripherals(withServices: nil)
                completion(nil, nil)
            }
        }

        switch currentState {
        case .available: doDiscover(error: nil)
        case .unavailable:
            completion(nil, JSONRPCError.applicationError(
                data: "Bluetooth unavailable: \(central.state)"))
        case .unknown:
            onBluetoothReadyTasks.insert(doDiscover, at: 0)
        }
    }

    func getUUID(forPeripheral peripheral: CBPeripheral) -> CBUUID {
        return CBUUID(string: peripheral.identifier.uuidString)
    }

    private func getCanonicalUUIDString(uuid: String) -> String {
        var canonical = "0000" + uuid
        canonical += "-0000-1000-8000-00805f9b34fb"
        return canonical
    }

    // MARK: - CBCentralManager discovery / connect delegates

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi rssiRaw: NSNumber) {
        let rssi = RSSI(rawValue: rssiRaw)
        if case .valid(let value) = rssi, value < BLESession.MinimumSignalStrength { return }
        if peripheral.state != .disconnected { return }
        if filters?.contains(where: { $0.matches(peripheral, advertisementData) }) != true { return }

        let uuid = getUUID(forPeripheral: peripheral)
        let peripheralData: [String: Any] = [
            "name": peripheral.name ?? "",
            "peripheralId": uuid.uuidString,
            "rssi": rssi.rawValue as Any
        ]
        reportedPeripherals![uuid] = peripheral
        sendRemoteRequest("didDiscoverPeripheral", withParams: peripheralData)
    }

    func connect(withParams params: [String: Any], completion: @escaping JSONRPCCompletionHandler) throws {
        guard let peripheralIdString = params["peripheralId"] as? String else {
            throw JSONRPCError.invalidParams(data: "missing or invalid peripheralId")
        }
        let peripheralId = CBUUID(string: peripheralIdString)
        guard let peripheral = reportedPeripherals?[peripheralId] else {
            throw JSONRPCError.invalidParams(data: "invalid peripheralId: \(peripheralId)")
        }
        if connectionCompletion != nil {
            throw JSONRPCError.invalidRequest(data: "connection already pending")
        }
        connectionCompletion = completion
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = peripheralDelegateHelper
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == connectedPeripheral,
              let completion = connectionCompletion else { return }
        if let error = error {
            completion(nil, JSONRPCError.applicationError(data: error.localizedDescription))
        } else {
            completion(nil, nil)
        }
        connectionCompletion = nil
    }

    // MARK: - write / read / notifications

    func write(withParams params: [String: Any], completion: @escaping JSONRPCCompletionHandler) throws {
        let buffer = try EncodingHelpers.decodeBuffer(fromJSON: params)
        let withResponse = params["withResponse"] as? Bool

        getEndpoint(for: "write request", withParams: params, blockedBy: .ExcludeWrites) { endpoint, error in
            if let error = error { completion(nil, error); return }
            guard let peripheral = self.connectedPeripheral else {
                completion(nil, JSONRPCError.internalError(data: "write without connected peripheral"))
                return
            }
            guard let endpoint = endpoint else {
                completion(nil, JSONRPCError.internalError(data: "failed to find characteristic"))
                return
            }
            let writeType = (withResponse ?? !endpoint.properties.contains(.writeWithoutResponse)) ?
                CBCharacteristicWriteType.withResponse : CBCharacteristicWriteType.withoutResponse
            peripheral.writeValue(buffer, for: endpoint, type: writeType)
            completion(buffer.count, nil)
        }
    }

    private func read(withParams params: [String: Any], completion: @escaping JSONRPCCompletionHandler) throws {
        let requestedEncoding = params["encoding"] as? String ?? "base64"
        let startNotifications = params["startNotifications"] as? Bool ?? false

        getEndpoint(for: "read request", withParams: params, blockedBy: .ExcludeReads) { endpoint, error in
            if let error = error { completion(nil, error); return }
            guard let peripheral = self.connectedPeripheral else {
                completion(nil, JSONRPCError.internalError(data: "read without connected peripheral"))
                return
            }
            guard let endpoint = endpoint else {
                completion(nil, JSONRPCError.internalError(data: "failed to find characteristic"))
                return
            }

            self.addCallback(toRegistry: &self.valueUpdateHandlers, forKey: endpoint) { error in
                if let error = error {
                    completion(nil, JSONRPCError.applicationError(data: error.localizedDescription))
                    return
                }
                guard let value = endpoint.value else {
                    completion(nil, JSONRPCError.internalError(data: "failed to retrieve value"))
                    return
                }
                guard let json = EncodingHelpers.encodeBuffer(value, withEncoding: requestedEncoding) else {
                    completion(nil, JSONRPCError.invalidRequest(data: "failed to encode result"))
                    return
                }
                completion(json, nil)
            }

            if startNotifications {
                self.watchedCharacteristics.insert(endpoint)
                peripheral.setNotifyValue(true, for: endpoint)
            }
            peripheral.readValue(for: endpoint)
        }
    }

    private func startNotifications(withParams params: [String: Any],
                                    completion: @escaping JSONRPCCompletionHandler) {
        getEndpoint(for: "notification request", withParams: params, blockedBy: .ExcludeReads) { endpoint, error in
            if let error = error { completion(nil, error); return }
            guard let peripheral = self.connectedPeripheral else {
                completion(nil, JSONRPCError.internalError(data: "notification without connected peripheral"))
                return
            }
            guard let endpoint = endpoint else {
                completion(nil, JSONRPCError.internalError(data: "failed to find characteristic"))
                return
            }
            self.watchedCharacteristics.insert(endpoint)
            peripheral.setNotifyValue(true, for: endpoint)
            completion(nil, nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == connectedPeripheral else { return }

        if let handlers = valueUpdateHandlers.removeValue(forKey: characteristic) {
            for handler in handlers { handler(error) }
        }

        if watchedCharacteristics.contains(characteristic) {
            guard let value = characteristic.value else { return }
            guard let json = EncodingHelpers.encodeBuffer(value, withEncoding: "base64") else { return }
            sendRemoteRequest("characteristicDidChange", withParams: json)
        }
    }

    private func stopNotifications(withParams params: [String: Any], completion: @escaping JSONRPCCompletionHandler) {
        getEndpoint(for: "stopNotifications", withParams: params, blockedBy: .ExcludeReads) { endpoint, error in
            if let error = error { completion(nil, error); return }
            guard let endpoint = endpoint else {
                completion(nil, JSONRPCError.invalidRequest(data: "failed to find characteristic"))
                return
            }
            self.watchedCharacteristics.remove(endpoint)
            endpoint.service?.peripheral?.setNotifyValue(false, for: endpoint)
            completion(nil, nil)
        }
    }

    // MARK: - getEndpoint helper

    typealias GetEndpointCompletionHandler = (_ result: CBCharacteristic?, _ error: JSONRPCError?) -> Void

    private func getEndpoint(for context: String, withParams params: [String: Any],
                             blockedBy checkFlag: GATTBlockListStatus,
                             completion: @escaping GetEndpointCompletionHandler) {
        guard let peripheral = connectedPeripheral else {
            completion(nil, JSONRPCError.invalidRequest(data: "no peripheral for \(context)"))
            return
        }
        if peripheral.state != .connected {
            central.cancelPeripheralConnection(peripheral)
            connectedPeripheral = nil
            completion(nil, JSONRPCError.invalidRequest(data: "not connected for \(context)"))
            return
        }
        guard let serviceName = params["serviceId"] else {
            completion(nil, JSONRPCError.invalidParams(data: "missing service UUID for \(context)"))
            return
        }
        guard let serviceId = GATTHelpers.getUUID(forService: serviceName) else {
            completion(nil, JSONRPCError.invalidParams(data: "could not determine service UUID for \(serviceName)"))
            return
        }
        if allowedServices?.contains(serviceId) != true {
            completion(nil, JSONRPCError.invalidParams(data: "unexpected service: \(serviceName)"))
            return
        }
        if let blockStatus = GATTHelpers.getBlockListStatus(ofUUID: serviceId), blockStatus.contains(checkFlag) {
            completion(nil, JSONRPCError.invalidParams(data: "service block-listed: \(serviceName)"))
            return
        }
        guard let characteristicName = params["characteristicId"] else {
            completion(nil, JSONRPCError.invalidParams(data: "missing characteristic UUID for \(context)"))
            return
        }
        guard let characteristicId = GATTHelpers.getUUID(forCharacteristic: characteristicName) else {
            completion(nil, JSONRPCError.invalidParams(
                data: "could not determine characteristic UUID for \(characteristicName)"))
            return
        }
        if let blockStatus = GATTHelpers.getBlockListStatus(ofUUID: characteristicId) {
            if blockStatus.contains(checkFlag) {
                completion(nil, JSONRPCError.invalidParams(
                    data: "characteristic block-listed: \(characteristicName)"))
                return
            }
        }
        guard let service = connectedPeripheral?.services?.first(where: { $0.uuid == serviceId }) else {
            completion(nil, JSONRPCError.invalidParams(data: "could not find service \(serviceName)"))
            return
        }

        func onCharacteristicsDiscovered(_ error: Error?) {
            if let error = error {
                completion(nil, JSONRPCError.applicationError(data: error.localizedDescription))
                return
            }
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicId }) else {
                completion(nil, JSONRPCError.invalidParams(
                    data: "could not find characteristic \(characteristicName) on \(serviceName)"))
                return
            }
            completion(characteristic, nil)
        }

        if service.characteristics == nil {
            addCallback(toRegistry: &characteristicDiscoveryCompletion,
                        forKey: serviceId, callback: onCharacteristicsDiscovered)
            peripheral.discoverCharacteristics(nil, for: service)
        } else {
            onCharacteristicsDiscovered(nil)
        }
    }

    func addCallback<T, U>(toRegistry registry: inout [T: [U]], forKey key: T, callback: U) {
        registry[key, default: []].append(callback)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let handlers = characteristicDiscoveryCompletion.removeValue(forKey: service.uuid) else { return }
        for handler in handlers { handler(error) }
    }

    // MARK: - JSON-RPC dispatch

    override func didReceiveCall(_ method: String, withParams params: [String: Any],
                                 completion: @escaping JSONRPCCompletionHandler) throws {
        switch method {
        case "discover":
            try discover(withParams: params, completion: completion)
        case "connect":
            try connect(withParams: params, completion: completion)
        case "write":
            try write(withParams: params, completion: completion)
        case "read":
            try read(withParams: params, completion: completion)
        case "startNotifications":
            startNotifications(withParams: params, completion: completion)
        case "stopNotifications":
            stopNotifications(withParams: params, completion: completion)
        case "getServices":
            var services = [String]()
            connectedPeripheral?.services?.forEach {
                services.append(getCanonicalUUIDString(uuid: $0.uuid.uuidString))
            }
            completion(services, nil)
        default:
            try super.didReceiveCall(method, withParams: params, completion: completion)
        }
    }
}

// MARK: - BLEScanFilter

struct BLEScanFilter {
    public let name: String?
    public let namePrefix: String?
    public let requiredServices: Set<CBUUID>?
    public let manufacturerData: [UInt16: [String: [UInt8]]]?

    public var isEmpty: Bool {
        return (name?.isEmpty ?? true) &&
               (namePrefix?.isEmpty ?? true) &&
               (requiredServices?.isEmpty ?? true) &&
               (manufacturerData?.isEmpty ?? true)
    }

    init(fromJSON json: [String: Any]) throws {
        self.name = json["name"] as? String
        self.namePrefix = json["namePrefix"] as? String

        if let requiredServices = json["services"] as? [Any] {
            self.requiredServices = Set<CBUUID>(try requiredServices.map({
                guard let uuid = GATTHelpers.getUUID(forService: $0) else {
                    throw JSONRPCError.invalidParams(data: "could not determine UUID for service \($0)")
                }
                return uuid
            }))
        } else {
            self.requiredServices = nil
        }

        if let manufacturerData = json["manufacturerData"] as? [String: Any] {
            var dict = [UInt16: [String: [UInt8]]]()
            for (k, v) in manufacturerData {
                guard let key = UInt16(k), var values = v as? [String: [UInt8]] else {
                    throw JSONRPCError.invalidParams(data: "could not parse manufacturer data")
                }
                guard let dataPrefix = values["dataPrefix"] else {
                    throw JSONRPCError.invalidParams(data: "no data prefix specified")
                }
                let mask = values["mask"] ?? [UInt8](repeating: 0xFF, count: dataPrefix.count)
                values["mask"] = mask
                if dataPrefix.count != mask.count {
                    throw JSONRPCError.invalidParams(data: "data prefix length does not match mask length")
                }
                dict[key] = values
            }
            self.manufacturerData = dict
        } else {
            self.manufacturerData = nil
        }
    }

    public func matches(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool {
        if let peripheralName = peripheral.name {
            if let name = name, !name.isEmpty, peripheralName != name { return false }
            if let namePrefix = namePrefix, !namePrefix.isEmpty,
               !peripheralName.starts(with: namePrefix) { return false }
        } else {
            if !((name?.isEmpty ?? true) && (namePrefix?.isEmpty ?? true)) { return false }
        }

        if let required = requiredServices, !required.isEmpty {
            var available = Set<CBUUID>()
            if let services = peripheral.services { available.formUnion(services.map { $0.uuid }) }
            if let serviceUUIDs = advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID] {
                available.formUnion(serviceUUIDs)
            }
            if !required.isSubset(of: available) { return false }
        }

        if let manufacturer = manufacturerData, !manufacturer.isEmpty {
            for i in manufacturer {
                let id = i.key
                guard let prefix = i.value["dataPrefix"], let mask = i.value["mask"] else { return false }
                let maskedPrefix = prefix.enumerated().map { $0.element & mask[$0.offset] }
                if let deviceData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                    let deviceId = UInt16(deviceData[0]) | UInt16(deviceData[1]) << 8
                    let devicePrefix = [UInt8](deviceData).dropFirst(2).prefix(mask.count)
                    let maskedDevice = devicePrefix.enumerated().map { $0.element & mask[$0.offset] }
                    if deviceId != id || maskedPrefix != maskedDevice { return false }
                } else {
                    return false
                }
            }
        }

        return true
    }
}
