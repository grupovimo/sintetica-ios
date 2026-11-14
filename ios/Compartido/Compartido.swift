import ActivityKit
import Foundation
import Security

/// Lo que comparten la app y sus widgets: la sesión (en un grupo del llavero
/// que ven las dos) y el timer en vivo (Live Activity y Dynamic Island).
enum LlaveroCompartido {
    /// El grupo del llavero (con el prefijo del equipo; ver los .entitlements).
    static let grupo = "M6935MSNQB.com.sinteticalabs.compartido"
    private static let servicio = "com.sinteticalabs.compartido"

    struct Sesion: Codable, Sendable {
        let servidor: String
        let token: String
    }

    private static func consulta() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio,
         kSecAttrAccount as String: "sesion", kSecAttrAccessGroup as String: grupo]
    }

    /// La guarda la app al entrar y al abrirse (si no hay token, la borra).
    static func guardar(servidor: String, token: String) {
        SecItemDelete(consulta() as CFDictionary)
        guard !token.isEmpty, let d = try? JSONEncoder().encode(Sesion(servidor: servidor, token: token)) else { return }
        var q = consulta()
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func leer() -> Sesion? {
        var q = consulta()
        q[kSecReturnData as String] = true
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return try? JSONDecoder().decode(Sesion.self, from: d)
    }
}

/// El timer de la S1 en la pantalla bloqueada y en la Dynamic Island.
struct TimerAtributos: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Cuándo termina (corriendo) o cuánto le falta (en pausa).
        var fin: Date
        var pausado: Bool
        var restante: TimeInterval
    }

    /// "La pasta".
    var nombre: String
    /// Su nombre ("Ivy").
    var robot: String
}

enum TimerEnVivo {
    /// Empieza (o reemplaza) el timer en vivo. Sin permiso, no hace nada.
    static func empezar(nombre: String, robot: String, minutos: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        terminar()
        let fin = Date().addingTimeInterval(minutos * 60)
        let estado = TimerAtributos.ContentState(fin: fin, pausado: false, restante: minutos * 60)
        _ = try? Activity.request(attributes: TimerAtributos(nombre: nombre, robot: robot),
                                  content: ActivityContent(state: estado, staleDate: fin.addingTimeInterval(60)))
    }

    /// Pausa o sigue (con lo que le faltaba).
    static func pausar(_ pausado: Bool, restante: TimeInterval) {
        let estado = TimerAtributos.ContentState(fin: Date().addingTimeInterval(restante), pausado: pausado, restante: restante)
        for a in Activity<TimerAtributos>.activities {
            Task { await a.update(ActivityContent(state: estado, staleDate: nil)) }
        }
    }

    static func terminar() {
        for a in Activity<TimerAtributos>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
