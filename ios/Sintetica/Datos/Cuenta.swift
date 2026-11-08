import Foundation
import Observation
import Security

/// La sesión en la nube: el servidor, el email y el token (en el Keychain).
@MainActor
@Observable
final class Cuenta {
    static let compartida = Cuenta()
    /// En local, la API corre en la Mac: http://<la IP de la Mac>:8080.
    static let servidorPorDefecto = "http://192.168.1.10:8080"

    var servidor: String { didSet { UserDefaults.standard.set(servidor, forKey: "servidor") } }
    var email: String { didSet { UserDefaults.standard.set(email, forKey: "email") } }
    private(set) var token: String
    var activa: Bool { !token.isEmpty }
    var api: ApiSintetica { ApiSintetica(servidor: servidor, token: token) }

    @ObservationIgnored private let servicio = "com.sinteticalabs.app.cuenta"

    init() {
        servidor = UserDefaults.standard.string(forKey: "servidor") ?? Cuenta.servidorPorDefecto
        email = UserDefaults.standard.string(forKey: "email") ?? ""
        token = ""
        token = leerToken() ?? ""
    }

    func entrar(_ t: String) {
        token = t
        guardarToken(t)
    }

    func salir() {
        token = ""
        SecItemDelete(consulta() as CFDictionary)
    }

    private func consulta() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio, kSecAttrAccount as String: "token"]
    }

    private func leerToken() -> String? {
        var q = consulta()
        q[kSecReturnData as String] = true
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func guardarToken(_ t: String) {
        SecItemDelete(consulta() as CFDictionary)
        var q = consulta()
        q[kSecValueData as String] = Data(t.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

struct ErrorApi: LocalizedError {
    let estado: Int
    let mensaje: String
    let detalle: String
    var errorDescription: String? { detalle.isEmpty ? mensaje : "\(mensaje): \(detalle)" }
}

/// Las credenciales MQTT que la API le da a un bicho (la app se las pasa por BLE).
struct Credenciales: Sendable { let url: String; let usuario: String; let clave: String }

/// Un bicho de la cuenta.
struct BichoNube: Identifiable, Sendable {
    let id: String
    let nombre: String
    let perfil: String
    let conectado: Bool
    let virtual: Bool
    let estadoCrudo: [UInt8]?
}

/// Un firmware firmado para un perfil.
struct FirmwareNube: Identifiable, Sendable { let id: Int; let version: String; let tamano: Int }

/// Un evento en vivo (SSE).
struct EventoNube { let tipo: String; let datos: [String: Any]; var bicho = "" }
extension EventoNube: @unchecked Sendable {}

/// La API de SintéticaOS (docs/nube.md).
struct ApiSintetica: Sendable {
    let servidor: String
    var token = ""

    func pedido(_ ruta: String, _ metodo: String = "GET", _ cuerpo: [String: Any]? = nil, encabezados: [String: String] = [:]) throws -> URLRequest {
        guard let url = URL(string: servidor.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + ruta) else {
            throw ErrorApi(estado: 0, mensaje: "El servidor no es una URL válida.", detalle: servidor)
        }
        var r = URLRequest(url: url, timeoutInterval: 45)
        r.httpMethod = metodo
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in encabezados { r.setValue(v, forHTTPHeaderField: k) }
        if let cuerpo {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        }
        return r
    }

    func pedir(_ ruta: String, _ metodo: String = "GET", _ cuerpo: [String: Any]? = nil, encabezados: [String: String] = [:]) async throws -> [String: Any] {
        let r = try pedido(ruta, metodo, cuerpo, encabezados: encabezados)
        let (datos, resp): (Data, URLResponse)
        do { (datos, resp) = try await URLSession.shared.data(for: r) } catch {
            throw ErrorApi(estado: 0, mensaje: "No me pude conectar con \(servidor).", detalle: "")
        }
        let estado = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] ?? [:]
        if estado >= 400 {
            throw ErrorApi(estado: estado, mensaje: obj["error"] as? String ?? "Error \(estado)", detalle: obj["detalle"] as? String ?? "")
        }
        return obj
    }

    func pedirEnlace(_ email: String) async throws { _ = try await pedir("/v1/sesion/enlace", "POST", ["email": email, "cliente": "app"]) }

    /// Con el código del mail (o el token del link). Devuelve el token de la sesión.
    func canjear(email: String? = nil, codigo: String? = nil, tokenEnlace: String? = nil) async throws -> String {
        var c: [String: Any] = ["descripcion": "App de iOS"]
        if let tokenEnlace { c["token"] = tokenEnlace } else { c["email"] = email ?? ""; c["codigo"] = codigo ?? "" }
        let r = try await pedir("/v1/sesion/canjear", "POST", c)
        guard let t = r["token"] as? String else { throw ErrorApi(estado: 0, mensaje: "La API no dio el token.", detalle: "") }
        return t
    }

    func salir() async { _ = try? await pedir("/v1/sesion", "DELETE") }

    func bichos() async throws -> [BichoNube] {
        ((try await pedir("/v1/bichos"))["bichos"] as? [[String: Any]] ?? []).map(Self.aBicho)
    }

    func bicho(_ id: String) async throws -> BichoNube { Self.aBicho(try await pedir("/v1/bichos/\(id)")) }

    private static func aBicho(_ o: [String: Any]) -> BichoNube {
        let est = o["estado"] as? [String: Any]
        let crudo = (est?["crudo"] as? String).flatMap { Data(base64Encoded: $0) }.map { [UInt8]($0) }
        let apodo = o["apodo"] as? String ?? ""
        return BichoNube(id: o["id"] as? String ?? "", nombre: apodo.isEmpty ? (est?["nombre"] as? String ?? "Bicho") : apodo,
                         perfil: o["perfil"] as? String ?? "", conectado: o["conectado"] as? Bool ?? false,
                         virtual: o["virtual"] as? Bool ?? false, estadoCrudo: crudo)
    }

    func reclamar(_ id: String, perfil: String) async throws -> Credenciales {
        let m = (try await pedir("/v1/bichos/reclamar", "POST", ["id": id, "perfil": perfil]))["mqtt"] as? [String: Any] ?? [:]
        guard let url = m["url"] as? String, let usuario = m["usuario"] as? String, let clave = m["clave"] as? String else {
            throw ErrorApi(estado: 0, mensaje: "La API no dio las credenciales.", detalle: "")
        }
        return Credenciales(url: url, usuario: usuario, clave: clave)
    }

    func esperarReclamo(_ id: String, segundos: Int = 40) async throws -> Bool {
        (try await pedir("/v1/bichos/\(id)/reclamo?esperar=\(segundos)"))["sumado"] as? Bool ?? false
    }

    /// Un marco del protocolo, por la nube. Devuelve las respuestas que da la API misma.
    func marco(_ id: String, car: Int, datos: [UInt8], conexion: String) async throws -> [(Int, [UInt8])] {
        let r = try await pedir("/v1/bichos/\(id)/marcos", "POST", ["car": car, "datos": Data(datos).base64EncodedString()],
                                encabezados: ["X-Conexion": conexion])
        return (r["respuestas"] as? [[String: Any]] ?? []).compactMap { o in
            guard let c = o["car"] as? Int, let d = (o["datos"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return (c, [UInt8](d))
        }
    }

    func firmwares(perfil: String) async throws -> [FirmwareNube] {
        ((try await pedir("/v1/firmwares?perfil=\(perfil)"))["firmwares"] as? [[String: Any]] ?? []).compactMap { o in
            guard let id = o["id"] as? Int, let v = o["version"] as? String else { return nil }
            return FirmwareNube(id: id, version: v, tamano: o["tamano"] as? Int ?? 0)
        }
    }

    /// Los bytes del manifiesto firmado (para mandarlo por BLE).
    func manifiesto(_ id: Int) async throws -> [UInt8] {
        guard let s = (try await pedir("/v1/firmwares/\(id)/manifiesto"))["manifiesto"] as? String, let d = Data(base64Encoded: s) else {
            throw ErrorApi(estado: 0, mensaje: "La API no dio el manifiesto.", detalle: "")
        }
        return [UInt8](d)
    }

    func binario(_ id: Int) async throws -> [UInt8] {
        let (d, r) = try await URLSession.shared.data(for: try pedido("/v1/firmwares/\(id)/binario"))
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw ErrorApi(estado: 0, mensaje: "No pude bajar el firmware.", detalle: "") }
        return [UInt8](d)
    }

    /// Los eventos en vivo de un bicho (SSE).
    func eventos(_ id: String) -> AsyncThrowingStream<EventoNube, Error> {
        AsyncThrowingStream { cont in
            let tarea = Task {
                do {
                    var r = try pedido("/v1/bichos/\(id)/eventos")
                    r.timeoutInterval = 3600
                    r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, _) = try await URLSession.shared.bytes(for: r)
                    var tipo = ""
                    for try await linea in bytes.lines {
                        if linea.hasPrefix("event: ") { tipo = String(linea.dropFirst(7)) }
                        else if linea.hasPrefix("data: "),
                                let o = try? JSONSerialization.jsonObject(with: Data(linea.dropFirst(6).utf8)) as? [String: Any] {
                            cont.yield(EventoNube(tipo: tipo, datos: o["datos"] as? [String: Any] ?? [:]))
                        }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in tarea.cancel() }
        }
    }
}
