import Foundation

// La nube de la v1.9 (docs/nube.md): amigos y toques, agenda, presencia,
// hábitos, avisos de afuera, música y charla con IA.

struct Amigo: Identifiable, Equatable {
    let id: Int
    var nombre: String
    var robots: [String]
    var todos: Bool
    var conectado: Bool

    init(_ o: [String: Any]) {
        id = (o["id"] as? NSNumber)?.intValue ?? 0
        nombre = o["nombre"] as? String ?? "Amigo"
        robots = (o["robots"] as? [String] ?? []).map { $0.uppercased() }
        todos = o["todos"] as? Bool ?? true
        conectado = o["conectado"] as? Bool ?? false
    }

    func recibe(_ robot: String) -> Bool { todos || robots.contains(robot.uppercased()) }

    /// Los robots míos que reciben sus toques después de prender o apagar uno
    /// (nil = todos; nil también como `todos` para "Todos").
    static func robotsCon(_ a: Amigo, alternando id: String?, mios: [String]) -> [String]? {
        guard let id else { return a.todos ? [] : nil }
        let ya = a.todos ? mios : a.robots
        let l = ya.contains(id) ? ya.filter { $0 != id } : ya + [id]
        return l.count == mios.count && Set(l) == Set(mios) ? nil : l
    }
}

struct Invitacion: Equatable {
    let codigo: String, link: String, telegram: String, vence: Date?
    /// "ABCD-EFGH".
    var codigoLindo: String { codigo.count == 8 ? "\(codigo.prefix(4))-\(codigo.suffix(4))" : codigo }
}

/// Un código de amigo como lo escribe la gente: sin espacios ni guiones, en mayúsculas.
func limpiarCodigo(_ c: String) -> String { c.filter { !$0.isWhitespace && $0 != "-" }.uppercased() }

struct EventoAgenda: Identifiable, Equatable {
    let uid: String, titulo: String, inicio: Date?, todoElDia: Bool
    let inicioTexto: String
    var id: String { uid + inicioTexto }

    /// Los de día entero vienen como fecha (medianoche UTC): se leen como el día de esa fecha.
    var fecha: Date? {
        guard todoElDia, inicioTexto.count >= 10 else { return inicio }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: String(inicioTexto.prefix(10)) + " 12:00")
    }
}

struct Agenda: Equatable {
    var conectada = false
    var ics = ""
    var aviso = 10
    var proximos: [EventoAgenda] = []
    var error = ""

    init(_ o: [String: Any]) {
        conectada = o["conectada"] as? Bool ?? false
        ics = o["ics"] as? String ?? ""
        aviso = (o["aviso"] as? NSNumber)?.intValue ?? 10
        error = o["error"] as? String ?? ""
        proximos = (o["proximos"] as? [[String: Any]] ?? []).map { e in
            let i = e["inicio"] as? String ?? ""
            return EventoAgenda(uid: e["uid"] as? String ?? "", titulo: e["titulo"] as? String ?? "", inicio: fechaISO(i),
                                todoElDia: e["todoElDia"] as? Bool ?? false, inicioTexto: i)
        }
    }
}

struct Entrantes: Equatable {
    var url = "", token = "", mercadoPago = false, regenerar = false
    init(_ o: [String: Any]) {
        url = o["url"] as? String ?? ""
        token = o["token"] as? String ?? ""
        mercadoPago = o["mercadoPago"] as? Bool ?? false
        regenerar = o["regenerar"] as? Bool ?? false
    }
}

let TIPOS_ENTRANTE = ["pago", "mail", "github", "pedido", "otro"]
/// Qué hace con cada uno (el núcleo: compania.cpp): el pago, cara de emocionado; los demás, un globo.
let ENTRANTES: [String: (nombre: String, cara: String?, titulo: String, de: String, icono: String)] = [
    "pago": ("Pago", "emocionado", "$12.000", "Ana", "dollarsign.circle.fill"),
    "mail": ("Mail", nil, "Hola", "Ana", "envelope.fill"),
    "github": ("GitHub", nil, "PR #12", "ana", "chevron.left.forwardslash.chevron.right"),
    "pedido": ("Pedido", nil, "Pedido #8", "La tienda", "shippingbox.fill"),
    "otro": ("Otro", nil, "Aviso", "Vos", "bell.fill"),
]

struct Suena: Equatable { var sonando: Bool, titulo: String, artista: String }

struct Musica: Equatable {
    var disponible = false, conectada = false
    var nombre = ""
    var suena: Suena?
    init(_ o: [String: Any]) {
        disponible = o["disponible"] as? Bool ?? false
        conectada = o["conectada"] as? Bool ?? false
        nombre = o["nombre"] as? String ?? ""
        if let s = o["suena"] as? [String: Any] {
            suena = Suena(sonando: s["sonando"] as? Bool ?? false, titulo: s["titulo"] as? String ?? "", artista: s["artista"] as? String ?? "")
        }
    }
}

/// La charla: siempre está (sin IA charla el motor propio). quedan -1 = sin tope.
struct Charla: Equatable {
    var disponible = true, ia = false
    var quedan = -1, porDia = 0
    init(disponible: Bool = true, ia: Bool = false, quedan: Int = -1, porDia: Int = 0) {
        self.disponible = disponible; self.ia = ia; self.quedan = quedan; self.porDia = porDia
    }
    init(_ o: [String: Any]) {
        disponible = o["disponible"] as? Bool ?? true
        ia = o["ia"] as? Bool ?? false
        quedan = (o["quedan"] as? NSNumber)?.intValue ?? -1
        porDia = (o["porDia"] as? NSNumber)?.intValue ?? 0
        if o["sin_tope"] as? Bool == true { quedan = -1 }
    }
    var sinTope: Bool { quedan < 0 }
    var puede: Bool { sinTope || quedan > 0 }
}
let MAX_CHARLA = 200

/// Un hábito como lo ve la nube: su racha, si se hizo hoy y los últimos 60 días.
struct VistaHabito: Equatable {
    var indice: Int, nombre: String, racha: Int, hoy: Bool
    var dias: Set<String>

    init(_ o: [String: Any]) {
        indice = (o["indice"] as? NSNumber)?.intValue ?? 0
        nombre = o["nombre"] as? String ?? ""
        racha = (o["racha"] as? NSNumber)?.intValue ?? 0
        hoy = o["hoy"] as? Bool ?? false
        let d = o["dias"] as? [String: Any] ?? [:]
        dias = Set(d.filter { ($0.value as? Bool) == true }.keys)
    }
}

/// Las claves YYYY-MM-DD de los últimos n días (del más viejo a hoy), en la hora de acá.
func ultimosDias(_ n: Int, hoy: Date = Date(), calendario: Calendar = .current) -> [String] {
    (0 ..< n).compactMap { k in
        guard let d = calendario.date(byAdding: .day, value: k - (n - 1), to: hoy) else { return nil }
        let c = calendario.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Lo que aprendió la nube de tus horarios.
struct Horarios: Equatable {
    var llegas = "", salis = "", dormis = ""
    var seguridad = 0.0
    var dias = 0
    init(_ o: [String: Any]) {
        llegas = o["llegas"] as? String ?? ""
        salis = o["salis"] as? String ?? ""
        dormis = o["dormis"] as? String ?? ""
        seguridad = (o["seguridad"] as? NSNumber)?.doubleValue ?? 0
        dias = (o["dias"] as? NSNumber)?.intValue ?? 0
    }
    /// De 0 a 5 rayitas.
    var segmentos: Int { Int((max(0, min(1, seguridad)) * 5).rounded()) }
}

extension ApiSintetica {
    private func objeto(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }
    private func json(_ c: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: c)) ?? Data("{}".utf8) }

    // --- Amigos ---
    func amigos() async throws -> [Amigo] { ((try await pedir("/v1/amigos"))["amigos"] as? [[String: Any]] ?? []).map { Amigo($0) } }

    func invitarAmigo() async throws -> Invitacion {
        let o = try await pedir("/v1/amigos/invitacion", "POST")
        return Invitacion(codigo: o["codigo"] as? String ?? "", link: o["link"] as? String ?? "", telegram: o["telegram"] as? String ?? "",
                          vence: (o["vence"] as? String).flatMap(fechaISO))
    }

    func aceptarAmigo(_ codigo: String) async throws -> Amigo { Amigo(try await pedir("/v1/amigos", "POST", ["codigo": codigo])) }
    func borrarAmigo(_ id: Int) async throws { _ = try await pedirCrudo("/v1/amigos/\(id)", "DELETE") }

    /// nil = todos los míos.
    func robotsDeAmigo(_ id: Int, _ robots: [String]?) async throws {
        let c: [String: Any] = ["robots": robots.map { $0 as Any } ?? NSNull()]
        _ = try await pedirCrudo("/v1/amigos/\(id)", "PUT", cuerpo: json(c))
    }

    /// Devuelve a cuántos robots le llegó y si fue por Telegram.
    func tocarAmigo(_ id: Int, tipo: String, expresion: String?, desde: String) async throws -> (robots: Int, telegram: Bool) {
        var c: [String: Any] = ["tipo": tipo, "desde": desde]
        if let expresion { c["expresion"] = expresion }
        let o = try await pedir("/v1/amigos/\(id)/toque", "POST", c)
        return ((o["robots"] as? NSNumber)?.intValue ?? 0, o["telegram"] as? Bool ?? false)
    }

    // --- Agenda ---
    func agenda() async throws -> Agenda { Agenda(try await pedir("/v1/agenda")) }
    func conectarAgenda(_ ics: String) async throws -> Agenda { Agenda(objeto(try await pedirCrudo("/v1/agenda", "PUT", cuerpo: json(["ics": ics])))) }
    func avisoAgenda(_ minutos: Int) async throws { _ = try await pedirCrudo("/v1/agenda", "PUT", cuerpo: json(["aviso": minutos])) }
    func sacarAgenda() async throws { _ = try await pedirCrudo("/v1/agenda", "DELETE") }

    // --- Presencia y horarios ---
    func presencia(_ id: String, llegaste: Bool) async throws { _ = try await pedir("/v1/bichos/\(id)/presencia", "POST", ["llegaste": llegaste]) }
    func horarios(_ id: String) async throws -> Horarios { Horarios(try await pedir("/v1/bichos/\(id)/horarios")) }

    // --- Hábitos ---
    func habitos(_ id: String) async throws -> [VistaHabito] {
        let d = try await pedirCrudo("/v1/bichos/\(id)/habitos", "GET")
        let l = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] ?? []
        return l.map { VistaHabito($0) }
    }

    func marcarHabito(_ id: String, _ i: Int, hecho: Bool) async throws -> VistaHabito {
        let o = try await pedir("/v1/bichos/\(id)/habitos/\(i)", "POST", ["hecho": hecho])
        return VistaHabito(o["habito"] as? [String: Any] ?? [:])
    }

    // --- Avisos de afuera ---
    func entrantes() async throws -> Entrantes { Entrantes(try await pedir("/v1/entrantes")) }
    func regenerarEntrantes() async throws -> Entrantes { Entrantes(try await pedir("/v1/entrantes", "POST")) }
    func guardarMercadoPago(_ token: String) async throws {
        _ = try await pedirCrudo("/v1/entrantes/mercadopago", "PUT", cuerpo: json(["accessToken": token]))
    }
    func sacarMercadoPago() async throws { _ = try await pedirCrudo("/v1/entrantes/mercadopago", "DELETE") }

    /// Manda uno de prueba; devuelve a cuántos robots llegó.
    func probarEntrante(token: String, tipo: String, titulo: String, de: String, robot: String) async throws -> Int {
        let o = try await pedir("/v1/entrantes/\(token)", "POST", ["tipo": tipo, "titulo": titulo, "de": de, "robot": robot])
        return (o["robots"] as? NSNumber)?.intValue ?? 0
    }

    // --- Música ---
    func musica() async throws -> Musica { Musica(try await pedir("/v1/musica")) }
    func enlaceSpotify() async throws -> String { (try await pedir("/v1/musica/spotify"))["url"] as? String ?? "" }
    func desconectarSpotify() async throws { _ = try await pedirCrudo("/v1/musica/spotify", "DELETE") }

    // --- Charla con IA ---
    func charla() async throws -> Charla { Charla(try await pedir("/v1/charla")) }

    /// La respuesta del robot, cuántas quedan hoy (-1 = sin tope) y de dónde salió ("motor" o "ia").
    func charlar(_ id: String, _ texto: String) async throws -> (texto: String, quedan: Int, origen: String) {
        let o = try await pedir("/v1/bichos/\(id)/charla", "POST", ["texto": texto])
        return (o["texto"] as? String ?? "", (o["quedan"] as? NSNumber)?.intValue ?? -1, o["origen"] as? String ?? "motor")
    }
}
