import CoreBluetooth
import Foundation

enum ErrorBle: LocalizedError {
    case apagado, sinPermiso, noEncontrado, desconectado, noEsUnBicho, tiempo, gatt(String)
    var errorDescription: String? {
        switch self {
        case .apagado: "Prendé el Bluetooth."
        case .sinPermiso: "Para encontrar tu bicho hace falta el permiso de Bluetooth (Ajustes › Sintética)."
        case .noEncontrado: "No encuentro el bicho. Acercalo al celu y fijate que esté prendido."
        case .desconectado: "Se cortó la conexión con el bicho."
        case .noEsUnBicho: "Ese dispositivo no es un bicho."
        case .tiempo: "El bicho no contestó a tiempo."
        case let .gatt(m): m
        }
    }
}

/// La central de CoreBluetooth: busca bichos por el UUID del servicio y el id del anuncio.
@MainActor
final class Central: NSObject, CBCentralManagerDelegate {
    static let compartida = Central()
    private var manager: CBCentralManager!
    private var listo: [CheckedContinuation<Void, Error>] = []
    private var buscando: (id: String, c: CheckedContinuation<CBPeripheral, Error>)?
    private var conectando: [UUID: CheckedContinuation<Void, Error>] = [:]
    var alDesconectar: [UUID: () -> Void] = [:]

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
    }

    private func esperarEncendido() async throws {
        switch manager.state {
        case .poweredOn: return
        case .unauthorized: throw ErrorBle.sinPermiso
        case .poweredOff, .unsupported: throw ErrorBle.apagado
        default: try await withCheckedThrowingContinuation { listo.append($0) }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            let pendientes = listo
            listo.removeAll()
            for c in pendientes {
                switch central.state {
                case .poweredOn: c.resume()
                case .unauthorized: c.resume(throwing: ErrorBle.sinPermiso)
                case .unknown, .resetting: listo.append(c)
                default: c.resume(throwing: ErrorBle.apagado)
                }
            }
        }
    }

    /// Busca el bicho con este id (el del QR) durante unos segundos.
    func buscar(id: String, segundos: Double = 20) async throws -> CBPeripheral {
        try await esperarEncendido()
        return try await withCheckedThrowingContinuation { c in
            buscando = (id, c)
            manager.scanForPeripherals(withServices: [Uuids.servicio], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(segundos))
                if let b = self.buscando, b.id == id {
                    self.buscando = nil
                    self.manager.stopScan()
                    b.c.resume(throwing: ErrorBle.noEncontrado)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let datos = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { Array($0) }
        MainActor.assumeIsolated {
            guard let b = buscando, idDeAnuncio(datos) == b.id else { return }
            buscando = nil
            manager.stopScan()
            b.c.resume(returning: p)
        }
    }

    func conectar(_ p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conectando[p.identifier] = c
            manager.connect(p)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated { conectando.removeValue(forKey: p.identifier)?.resume() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { conectando.removeValue(forKey: p.identifier)?.resume(throwing: error ?? ErrorBle.desconectado) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            conectando.removeValue(forKey: p.identifier)?.resume(throwing: ErrorBle.desconectado)
            alDesconectar[p.identifier]?()
        }
    }

    func desconectar(_ p: CBPeripheral) { manager.cancelPeripheralConnection(p) }
}

/// BLE con CoreBluetooth: una operación por vez y notificaciones en Config, Comando y Estado.
@MainActor
final class TransporteBle: NSObject, Transporte, CBPeripheralDelegate {
    let difusor = Difusor()
    private let periferico: CBPeripheral
    private var caracteristicas: [Car: CBCharacteristic] = [:]
    private var pendiente: CheckedContinuation<[UInt8], Error>?
    /// Cuenta las operaciones: el plazo de una no tiene que cortar a la que vino después.
    private var numeroOperacion = 0

    init(_ p: CBPeripheral) {
        periferico = p
        super.init()
        p.delegate = self
    }

    private func operacion(_ lanzar: () -> Void) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { c in
            pendiente = c
            numeroOperacion += 1
            let n = numeroOperacion
            lanzar()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if n == self.numeroOperacion, let p = self.pendiente { self.pendiente = nil; p.resume(throwing: ErrorBle.tiempo) }
            }
        }
    }

    private func terminar(_ r: Result<[UInt8], Error>) {
        guard let p = pendiente else { return }
        pendiente = nil
        p.resume(with: r)
    }

    func conectar() async throws {
        Central.compartida.alDesconectar[periferico.identifier] = { [weak self] in self?.terminar(.failure(ErrorBle.desconectado)) }
        try await Central.compartida.conectar(periferico)
        _ = try await operacion { periferico.discoverServices([Uuids.servicio]) }
        guard let servicio = periferico.services?.first(where: { $0.uuid == Uuids.servicio }) else { throw ErrorBle.noEsUnBicho }
        _ = try await operacion { periferico.discoverCharacteristics(Car.allCases.map(\.uuid), for: servicio) }
        for c in servicio.characteristics ?? [] { if let car = Car(uuid: c.uuid) { caracteristicas[car] = c } }
        for car in [Car.config, .comando, .estado, .imagen, .ota] {
            // Imagen es de la v1.2 y OTA de la v1.3: un firmware viejo no las tiene.
            guard let c = caracteristicas[car] else { if car == .imagen || car == .ota { continue }; throw ErrorBle.noEsUnBicho }
            _ = try await operacion { periferico.setNotifyValue(true, for: c) }
        }
    }

    func escribir(_ car: Car, _ datos: [UInt8]) async throws {
        guard let c = caracteristicas[car] else { throw ErrorBle.noEsUnBicho }
        _ = try await operacion { periferico.writeValue(Data(datos), for: c, type: .withResponse) }
    }

    func leerEstado() async throws -> [UInt8] {
        guard let c = caracteristicas[.estado] else { throw ErrorBle.noEsUnBicho }
        leyendoEstado = true
        return try await operacion { periferico.readValue(for: c) }
    }

    private var leyendoEstado = false

    func cerrar() { Central.compartida.desconectar(periferico) }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { terminar(error.map { .failure($0) } ?? .success([])) }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        MainActor.assumeIsolated { terminar(error.map { .failure($0) } ?? .success([])) }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { terminar(error.map { .failure($0) } ?? .success([])) }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { terminar(error.map { .failure(ErrorBle.gatt("El bicho no aceptó la escritura: \($0.localizedDescription)")) } ?? .success([])) }
    }

    /// Llega tanto por una lectura como por una notificación.
    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        let valor = c.value.map { Array($0) } ?? []
        let uuid = c.uuid
        MainActor.assumeIsolated {
            guard let car = Car(uuid: uuid) else { return }
            if car == .estado, leyendoEstado {
                leyendoEstado = false
                terminar(error.map { .failure($0) } ?? .success(valor))
            }
            difusor.emitir(car, valor)
        }
    }
}
