import Foundation

// Lo del Laboratorio que vive en la nube: el diario, la mudanza, el historial
// de la config, el firmware por WiFi y los tokens de tu IA.

let VARIABLES_ESTADO = ["energia", "animo", "afecto", "aburrimiento", "curiosidad", "sueno", "estres"]

/// El motor de vida en vivo: la respuesta al comando Vida ([0x9B][0]…), como
/// leerVida de sim/web/protocolo.js.
struct VidaEnVivo: Equatable {
    var estado: [String: Double] = [:]
    var rasgos: [String: Double] = [:]
    var dormido = false, sonando = false, superposicion = false
    var comportamiento = ""
    var visible = ""
    var candidatos: [(nombre: String, puntaje: Double)] = []

    static func == (a: VidaEnVivo, b: VidaEnVivo) -> Bool {
        a.estado == b.estado && a.comportamiento == b.comportamiento && a.dormido == b.dormido && a.sonando == b.sonando && a.visible == b.visible
    }
}

func leerVida(_ b: [UInt8]) -> VidaEnVivo? {
    guard b.count >= 2 + VARIABLES_ESTADO.count + RASGOS.count + 1, b[0] & 0x7F == Op.vida, b[1] == 0 else { return nil }
    var v = VidaEnVivo()
    var i = 2
    for e in VARIABLES_ESTADO { v.estado[e] = Double(b[i]) / 255; i += 1 }
    for r in RASGOS { v.rasgos[r] = Double(b[i]) / 255; i += 1 }
    let flags = b[i]; i += 1
    v.dormido = flags & 1 != 0
    v.sonando = flags & 2 != 0
    v.superposicion = flags & 4 != 0
    func campo() -> String? {
        guard i < b.count else { return nil }
        let n = Int(b[i])
        guard i + 1 + n <= b.count else { return nil }
        let s = String(decoding: b[(i + 1) ..< (i + 1 + n)], as: UTF8.self)
        i += 1 + n
        return s
    }
    v.comportamiento = campo() ?? ""
    v.visible = campo() ?? ""
    if i < b.count {
        let nc = Int(b[i]); i += 1
        for _ in 0 ..< nc {
            guard let n = campo(), i < b.count else { break }
            v.candidatos.append((n, Double(b[i]) / 100))
            i += 1
        }
    }
    return v
}

/// Lo que recuerda (GET /v1/bichos/{id}/memoria).
struct Memoria: Equatable {
    var dias = 0, racha = 0, rachaMax = 0, caricias = 0, toques = 0, sacudidas = 0
    var horas: [Int] = Array(repeating: 0, count: 24)
    var gustos: [String: Double] = [:]
    var hitos: [String] = []
    var deriva: [String: Double] = [:]

    init() {}

    init(_ o: [String: Any]) {
        func n(_ k: String) -> Int { (o[k] as? NSNumber)?.intValue ?? 0 }
        dias = n("dias"); racha = n("racha"); rachaMax = n("rachaMax")
        caricias = n("caricias"); toques = n("toques"); sacudidas = n("sacudidas")
        let h: [Int] = (o["horas"] as? [NSNumber] ?? []).map { $0.intValue }
        if h.count == 24 { horas = h }
        for (k, v) in o["gustos"] as? [String: Any] ?? [:] { gustos[k] = (v as? NSNumber)?.doubleValue ?? 0 }
        for (k, v) in o["deriva"] as? [String: Any] ?? [:] { deriva[k] = (v as? NSNumber)?.doubleValue ?? 0 }
        hitos = o["hitos"] as? [String] ?? []
    }

    /// La hora a la que más aparecés (si aparecés seguido), o nil.
    var horaPreferida: Int? {
        var mejor: Int?
        for (h, v) in horas.enumerated() where v >= 3 {
            if mejor == nil || v > horas[mejor!] { mejor = h }
        }
        return mejor
    }

    /// Los tres gustos más fuertes.
    var mejoresGustos: [String] {
        gustos.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }
}

let NOMBRES_HITO: [String: String] = [
    "primer-dia": "El primer día", "siete-dias": "Una semana", "treinta-dias": "Un mes",
    "cien-caricias": "100 caricias", "cien-dias": "100 días", "mil-caricias": "1000 caricias",
]

/// Una versión de la config (el historial).
struct VersionConfig: Identifiable, Equatable {
    let version: Int
    let autor: String
    let creada: Date?
    var id: Int { version }

    /// "mcp:Claude" se muestra "IA · Claude".
    var nombreAutor: String {
        switch autor {
        case "web": return "Web"
        case "app": return "App"
        case "bicho": return "En el robot"
        case "api": return "Nube"
        default: return autor.hasPrefix("mcp:") ? "IA · \(autor.dropFirst(4))" : autor
        }
    }
}

/// Un firmware disponible y una actualización por WiFi.
struct VersionFirmware: Identifiable, Equatable {
    let id: Int
    let version: String
    let notas: String
    let creado: Date?
}

struct Actualizacion: Identifiable, Equatable {
    let id: Int
    var version: String
    var estado: String  // enviada, descargando, instalada, confirmada, fallida
    var progreso: Int
    var creada: Date?

    init(_ o: [String: Any]) {
        id = (o["id"] as? NSNumber)?.intValue ?? 0
        version = o["version"] as? String ?? ""
        estado = o["estado"] as? String ?? ""
        progreso = (o["progreso"] as? NSNumber)?.intValue ?? 0
        creada = (o["creada"] as? String).flatMap(fechaISO)
    }

    var nombreEstado: String {
        ["enviada": "Enviada", "descargando": "Bajando", "instalada": "Probando", "confirmada": "Lista", "fallida": "Falló"][estado] ?? estado
    }
}

/// Un token para Claude Code (MCP).
struct TokenIA: Identifiable, Equatable {
    let id: String
    let nombre: String
    let usado: Date?
}

/// El comando para sumar el conector a Claude Code.
func comandoClaude(url: String, token: String) -> String {
    "claude mcp add --transport http sintetica \(url) --header \"Authorization: Bearer \(token)\""
}

extension ApiSintetica {
    func memoria(_ id: String) async throws -> (memoria: Memoria?, mudanzaPendiente: Bool) {
        let o = try await pedir("/v1/bichos/\(id)/memoria")
        let m = (o["memoria"] as? [String: Any]).map { Memoria($0) }
        return (m, o["mudanzaPendiente"] as? Bool ?? false)
    }

    func mudar(_ id: String, desde: String) async throws { _ = try await pedir("/v1/bichos/\(id)/mudar", "POST", ["desde": desde]) }

    func historialConfig(_ id: String) async throws -> [VersionConfig] {
        let l: [[String: Any]] = (try await pedir("/v1/bichos/\(id)/config/historial"))["versiones"] as? [[String: Any]] ?? []
        return l.map { v in
            VersionConfig(version: (v["version"] as? NSNumber)?.intValue ?? 0, autor: v["autor"] as? String ?? "",
                          creada: (v["creada"] as? String).flatMap(fechaISO))
        }
    }

    func restaurarConfig(_ id: String, version: Int) async throws { _ = try await pedir("/v1/bichos/\(id)/config/restaurar", "POST", ["version": version]) }

    func versionesFirmware(perfil: String) async throws -> [VersionFirmware] {
        let p = perfil.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? perfil
        let l: [[String: Any]] = (try await pedir("/v1/firmwares?perfil=\(p)"))["firmwares"] as? [[String: Any]] ?? []
        return l.compactMap { o in
            guard let id = (o["id"] as? NSNumber)?.intValue, let v = o["version"] as? String else { return nil }
            return VersionFirmware(id: id, version: v, notas: o["notas"] as? String ?? "", creado: (o["creado"] as? String).flatMap(fechaISO))
        }
    }

    func actualizaciones(_ id: String) async throws -> [Actualizacion] {
        ((try await pedir("/v1/bichos/\(id)/actualizaciones"))["actualizaciones"] as? [[String: Any]] ?? []).map { Actualizacion($0) }
    }

    func actualizar(_ id: String, firmware: Int) async throws -> Actualizacion {
        Actualizacion(try await pedir("/v1/bichos/\(id)/actualizar", "POST", ["firmware": firmware]))
    }

    func tokensIA() async throws -> [TokenIA] {
        let l: [[String: Any]] = (try await pedir("/v1/mcp/tokens"))["tokens"] as? [[String: Any]] ?? []
        return l.map { t in TokenIA(id: t["id"] as? String ?? "", nombre: t["nombre"] as? String ?? "Token", usado: (t["usado"] as? String).flatMap(fechaISO)) }
    }

    /// Un token nuevo: se ve una sola vez.
    func crearTokenIA() async throws -> (token: String, url: String) {
        let o = try await pedir("/v1/mcp/tokens", "POST", ["nombre": "Claude Code"])
        return (o["token"] as? String ?? "", o["url"] as? String ?? "")
    }

    /// Los sprites del robot (las caras de imagen): número, largo y CRC.
    func sprites(_ id: String) async throws -> [EspacioImagen] {
        let l: [[String: Any]] = (try await pedir("/v1/bichos/\(id)/sprites"))["sprites"] as? [[String: Any]] ?? []
        return l.compactMap { o in
            guard let n = (o["sprite"] as? NSNumber)?.intValue else { return nil }
            return EspacioImagen(espacio: n, largo: (o["largo"] as? NSNumber)?.uint32Value ?? 0, crc: (o["crc"] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    func sprite(_ id: String, _ n: Int) async throws -> [UInt8] { [UInt8](try await pedirCrudo("/v1/bichos/\(id)/sprites/\(n)", "GET")) }

    /// SVG, PNG, JPEG, GIF o QOI: la API lo recorta y lo achica.
    func subirSprite(_ id: String, _ n: Int, _ d: Data, tipo: String) async throws {
        _ = try await pedirCrudo("/v1/bichos/\(id)/sprites/\(n)", "PUT", cuerpo: d, tipo: tipo)
    }

    func borrarSprite(_ id: String, _ n: Int) async throws { _ = try await pedirCrudo("/v1/bichos/\(id)/sprites/\(n)", "DELETE") }

    func borrarTokenIA(_ id: String) async throws { _ = try await pedirCrudo("/v1/mcp/tokens/\(id)", "DELETE") }
}
