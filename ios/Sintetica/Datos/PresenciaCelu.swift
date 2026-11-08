import CoreBluetooth
import CoreLocation
import Foundation
import Observation
import UIKit

/// La presencia desde el iPhone del dueño (v1.9): cuando el robot está
/// vinculado por Bluetooth, la app se queda conectada en segundo plano (una
/// conexión pendiente que iOS completa cuando están cerca) y, de respaldo, una
/// geocerca de casa. En cada cambio, POST /v1/bichos/{id}/presencia. Todo es
/// opcional y se prende por robot en Su día.
@MainActor
@Observable
final class PresenciaCelu: NSObject {
    static let compartida = PresenciaCelu()

    private(set) var casaElegida = false
    private(set) var permisoUbicacion: CLAuthorizationStatus = .notDetermined
    private(set) var cambios = 0  // para que la UI se entere

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private let ubicacion = CLLocationManager()
    @ObservationIgnored private var perifericos: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var eligiendoCasa = false
    @ObservationIgnored private let datos = UserDefaults.standard

    static let radioCasa: CLLocationDistance = 150
    private static let region = "casa"

    // MARK: - Lo que se prende por robot

    func porBluetooth(_ id: String) -> Bool { datos.bool(forKey: "presencia.ble.\(id)") }
    func porCasa(_ id: String) -> Bool { datos.bool(forKey: "presencia.casa.\(id)") }
    func conoceAlRobot(_ id: String) -> Bool { datos.string(forKey: "periferico:\(id)") != nil }

    func ponerBluetooth(_ id: String, _ si: Bool) {
        datos.set(si, forKey: "presencia.ble.\(id)")
        cambios += 1
        arrancarBluetooth()
        if !si, let u = uuid(id), let p = perifericos[u] { central?.cancelPeripheralConnection(p) }
    }

    func ponerCasa(_ id: String, _ si: Bool) {
        datos.set(si, forKey: "presencia.casa.\(id)")
        cambios += 1
        if si, !casaElegida { elegirCasa() }
    }

    private var conBluetooth: [String] { idsCon("presencia.ble.") }
    private var conCasa: [String] { idsCon("presencia.casa.") }
    private func idsCon(_ prefijo: String) -> [String] {
        datos.dictionaryRepresentation().compactMap { k, v in
            k.hasPrefix(prefijo) && (v as? Bool) == true ? String(k.dropFirst(prefijo.count)) : nil
        }
    }

    private func uuid(_ id: String) -> UUID? { datos.string(forKey: "periferico:\(id)").flatMap(UUID.init(uuidString:)) }
    private func robotDe(_ u: UUID) -> String? { conBluetooth.first { uuid($0) == u } }

    // MARK: - Arranque (también cuando iOS relanza la app en segundo plano)

    func arrancar() {
        ubicacion.delegate = self
        permisoUbicacion = ubicacion.authorizationStatus
        casaElegida = ubicacion.monitoredRegions.contains { $0.identifier == Self.region }
        arrancarBluetooth()
    }

    private func arrancarBluetooth() {
        guard central == nil, !conBluetooth.isEmpty else {
            if central?.state == .poweredOn { conectarTodos() }
            return
        }
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.sinteticalabs.presencia"])
    }

    private func conectarTodos() {
        guard let c = central, c.state == .poweredOn else { return }
        let ids = conBluetooth.compactMap { uuid($0) }
        for p in c.retrievePeripherals(withIdentifiers: ids) where p.state != .connected && p.state != .connecting {
            perifericos[p.identifier] = p
            c.connect(p)  // pendiente: iOS la completa cuando estén cerca, aunque la app esté dormida
        }
    }

    // MARK: - Casa

    /// Pide la ubicación ("Siempre", para que funcione con la app cerrada) y marca acá como casa.
    func elegirCasa() {
        eligiendoCasa = true
        switch ubicacion.authorizationStatus {
        case .notDetermined: ubicacion.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            ubicacion.requestAlwaysAuthorization()
            ubicacion.requestLocation()
        case .authorizedAlways: ubicacion.requestLocation()
        default: eligiendoCasa = false
        }
    }

    func olvidarCasa() {
        for r in ubicacion.monitoredRegions where r.identifier == Self.region { ubicacion.stopMonitoring(for: r) }
        casaElegida = false
        cambios += 1
    }

    // MARK: - Avisar a la nube

    /// Avisa un cambio (no repite el mismo estado seguido) y le da unos segundos de segundo plano para mandarlo.
    func avisar(_ id: String, llegaste: Bool, ahora: Date = Date()) {
        guard PresenciaCelu.hayQueAvisar(anterior: datos.object(forKey: "presencia.ultimo.\(id)") as? Bool,
                                         hace: (datos.object(forKey: "presencia.en.\(id)") as? Date).map { ahora.timeIntervalSince($0) },
                                         llegaste: llegaste) else { return }
        datos.set(llegaste, forKey: "presencia.ultimo.\(id)")
        datos.set(ahora, forKey: "presencia.en.\(id)")
        guard Cuenta.compartida.activa else { return }
        let api = Cuenta.compartida.api
        var tarea = UIBackgroundTaskIdentifier.invalid
        tarea = UIApplication.shared.beginBackgroundTask(withName: "presencia") { UIApplication.shared.endBackgroundTask(tarea) }
        let t = tarea
        Task {
            try? await api.presencia(id, llegaste: llegaste)
            UIApplication.shared.endBackgroundTask(t)
        }
    }

    /// Un cambio de verdad: otro estado, o el mismo después de un buen rato (no rebota entre Bluetooth y la geocerca).
    nonisolated static func hayQueAvisar(anterior: Bool?, hace segundos: TimeInterval?, llegaste: Bool) -> Bool {
        guard let anterior else { return true }
        if anterior != llegaste { return (segundos ?? .infinity) > 60 }
        return (segundos ?? .infinity) > 3 * 3600
    }
}

extension PresenciaCelu: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        MainActor.assumeIsolated { conectarTodos() }
    }

    nonisolated func centralManager(_ c: CBCentralManager, willRestoreState estado: [String: Any]) {
        let l = estado[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        MainActor.assumeIsolated { for p in l { perifericos[p.identifier] = p } }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        let u = p.identifier
        MainActor.assumeIsolated { if let id = robotDe(u) { avisar(id, llegaste: true) } }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let u = p.identifier
        MainActor.assumeIsolated {
            guard let id = robotDe(u) else { return }
            avisar(id, llegaste: false)
            c.connect(p)  // y queda esperando la vuelta
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { if robotDe(p.identifier) != nil { c.connect(p) } }
    }
}

extension PresenciaCelu: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        MainActor.assumeIsolated {
            permisoUbicacion = s
            guard eligiendoCasa else { return }
            if s == .authorizedWhenInUse {
                m.requestAlwaysAuthorization()
                m.requestLocation()
            } else if s == .authorizedAlways {
                m.requestLocation()
            } else if s != .notDetermined {
                eligiendoCasa = false
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        MainActor.assumeIsolated {
            guard eligiendoCasa else { return }
            eligiendoCasa = false
            let r = CLCircularRegion(center: c, radius: Self.radioCasa, identifier: Self.region)
            r.notifyOnEntry = true
            r.notifyOnExit = true
            m.startMonitoring(for: r)
            casaElegida = true
            cambios += 1
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { eligiendoCasa = false }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion r: CLRegion) {
        MainActor.assumeIsolated { if r.identifier == Self.region { for id in conCasa { avisar(id, llegaste: true) } } }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion r: CLRegion) {
        MainActor.assumeIsolated { if r.identifier == Self.region { for id in conCasa { avisar(id, llegaste: false) } } }
    }
}
