import Foundation
import Observation
import Security

/// Un bicho que este celu ya vinculó. La clave es la que dio el bicho al vincular.
struct Vinculado: Codable, Equatable, Identifiable {
    var id: String
    var nombre: String
    var serie: String
    var clave: [UInt8]
}

/// Los bichos vinculados, guardados en el Keychain (las claves son secretas).
@MainActor
@Observable
final class Vinculados {
    static let compartidos = Vinculados()
    private(set) var todos: [Vinculado] = []
    @ObservationIgnored private let cuenta = "bichos"
    @ObservationIgnored private let servicio = "com.sinteticalabs.app.vinculados"

    init() { todos = Self.decodificar(leerKeychain()) }

    func buscar(_ id: String) -> Vinculado? { todos.first { $0.id == id } }

    func guardar(_ v: Vinculado) {
        todos = todos.filter { $0.id != v.id } + [v]
        escribirKeychain(Self.codificar(todos))
    }

    func olvidar(_ id: String) {
        todos.removeAll { $0.id == id }
        escribirKeychain(Self.codificar(todos))
    }

    static func codificar(_ l: [Vinculado]) -> Data { (try? JSONEncoder().encode(l)) ?? Data("[]".utf8) }
    static func decodificar(_ d: Data?) -> [Vinculado] { d.flatMap { try? JSONDecoder().decode([Vinculado].self, from: $0) } ?? [] }

    private func consulta() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio, kSecAttrAccount as String: cuenta]
    }

    private func leerKeychain() -> Data? {
        var q = consulta()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var r: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess ? r as? Data : nil
    }

    private func escribirKeychain(_ d: Data) {
        let q = consulta()
        let cambios: [String: Any] = [kSecValueData as String: d, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(q as CFDictionary, cambios as CFDictionary) == errSecItemNotFound {
            SecItemAdd(q.merging(cambios) { $1 } as CFDictionary, nil)
        }
    }
}
