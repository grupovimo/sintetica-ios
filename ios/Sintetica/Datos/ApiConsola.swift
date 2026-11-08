import Foundation

/// Un robot de la cuenta, como lo da la API (GET /v1/bichos).
struct RobotNube: Identifiable, Equatable {
    let id: String
    var perfil: String
    var apodo: String
    var virtual: Bool
    var conectado: Bool
    var ultimaConexion: Date?
    var estado: Estado?
    var sincroConfig: String

    init(_ o: [String: Any]) {
        id = (o["id"] as? String ?? "").uppercased()
        perfil = o["perfil"] as? String ?? ""
        apodo = o["apodo"] as? String ?? ""
        virtual = o["virtual"] as? Bool ?? false
        conectado = o["conectado"] as? Bool ?? false
        ultimaConexion = (o["ultimaConexion"] as? String).flatMap(fechaISO)
        estado = (o["estado"] as? [String: Any]).flatMap(estadoDeJSON)
        sincroConfig = (o["sincro"] as? [String: Any])?["config"] as? String ?? ""
    }
}

func fechaISO(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

/// El estado como lo manda la API en JSON (el mismo que por BLE, ya decodificado).
/// En pasos con tipos: el Xcode del CI no llega a inferir las expresiones largas.
func estadoDeJSON(_ o: [String: Any]) -> Estado? {
    if let s = o["crudo"] as? String, let d = Data(base64Encoded: s), let e = try? leerEstado([UInt8](d)) { return e }
    guard o["expresion"] != nil || o["nombre"] != nil else { return nil }
    func texto(_ k: String) -> String { o[k] as? String ?? "" }
    func si(_ k: String) -> Bool { o[k] as? Bool ?? false }
    func entero(_ k: String) -> Int? { (o[k] as? NSNumber)?.intValue }
    let p: [String: Any] = o["pantalla"] as? [String: Any] ?? [:]
    let ancho: Int = (p["ancho"] as? NSNumber)?.intValue ?? 0
    let alto: Int = (p["alto"] as? NSNumber)?.intValue ?? 172
    let redonda: Bool = p["redonda"] as? Bool ?? false
    let pantalla = Pantalla(ancho: ancho > 0 ? ancho : 320, alto: alto, redonda: redonda)
    let humor: Float = (o["humor"] as? NSNumber)?.floatValue ?? 0
    let modo: String = o["modo"] as? String ?? "mascota"
    var e = Estado(pantalla: pantalla, bateria: entero("bateria"), humor: humor, modo: modo,
                   dormido: si("dormido"), fija: si("fija"), emparejando: si("emparejando"), autenticado: true,
                   expresion: texto("expresion"), nombre: texto("nombre"), serie: texto("serie"), id: texto("id"))
    e.wifi = si("wifi")
    e.nube = si("nube")
    e.redConfigurada = si("redConfigurada")
    e.actualizando = si("actualizando")
    e.version = texto("version")
    e.perfil = texto("perfil")
    e.crcConfig = (o["crcConfig"] as? NSNumber)?.uint32Value ?? 0
    e.encendido = (o["encendido"] as? NSNumber)?.uint32Value ?? 0
    return e
}

// --- Integraciones (web/src/lib/consola/modulos/Integraciones.svelte) ---

struct AccionAuto: Codable, Equatable {
    var tipo: String          // decir, cara, modo, despertar, telegram, webhook o robot
    var texto: String? = nil  // telegram y decir (con plantillas)
    var url: String? = nil    // webhook
    var bicho: String? = nil  // robot: otro del mismo dueño
    var expresion: String? = nil  // cara, robot y (opcional) decir
    var modo: String? = nil   // modo
    var juego: String? = nil  // jugar: ppt, reflejos, mirada, dado o moneda

    static func nueva(_ tipo: String, otro: String?) -> AccionAuto {
        switch tipo {
        case "telegram": AccionAuto(tipo: tipo, texto: "{robot}: {evento}")
        case "webhook": AccionAuto(tipo: tipo, url: "https://")
        case "decir": AccionAuto(tipo: tipo, texto: "Buen día, {dueno}: {clima}")
        case "cara": AccionAuto(tipo: tipo, expresion: "contento")
        case "modo": AccionAuto(tipo: tipo, modo: "reloj")
        case "despertar": AccionAuto(tipo: tipo)
        case "jugar": AccionAuto(tipo: tipo, juego: "dado")
        default: AccionAuto(tipo: "robot", bicho: otro ?? "", expresion: "contento")
        }
    }
}

/// Las acciones, en el orden de la web.
let ACCIONES_AUTO: [(tipo: String, nombre: String, icono: String)] = [
    ("decir", "Decir", "bubble.left.fill"), ("cara", "Cara", "face.smiling"), ("modo", "Modo", "square.grid.2x2"),
    ("despertar", "Despertar", "sunrise.fill"), ("jugar", "Jugar", "gamecontroller.fill"), ("telegram", "Telegram", "paperplane.fill"), ("webhook", "URL", "link"),
    ("robot", "Otro robot", "person.2.fill"),
]
let MODOS_ACCION: [(String, String)] = [("mascota", "Compañía"), ("reloj", "Reloj"), ("pomodoro", "Pomodoro"), ("clima", "Clima")]
let PLANTILLAS_AUTO = ["{robot}", "{dueno}", "{texto}", "{hora}", "{clima}", "{temp}", "{max}", "{min}", "{ciudad}", "{bateria}", "{expresion}"]

struct Automatizacion: Codable, Equatable, Identifiable {
    var id: String
    var activa: Bool
    var cuando: String
    var valor: String? = nil
    /// cuando "hora": a esa hora (HH:MM) los días que diga (vacío = todos).
    var hora: String? = nil
    var dias: String? = nil
    var hacer: [AccionAuto]

    /// Cambia el cuándo y deja solo lo que ese cuándo usa (como la web).
    mutating func ponerCuando(_ k: String) {
        cuando = k
        if k != "expresion" { valor = nil }
        if k == "hora" { hora = hora ?? "08:00" } else { hora = nil; dias = nil }
    }

    /// Prende o apaga un día de "a una hora" (nunca deja ninguno; los 7 = todos).
    mutating func alternarDia(_ l: String) {
        let ya = dias ?? "LMXJVSD"
        let nuevo = DIAS_SEMANA.map(\.letra).filter { $0 == l ? !ya.contains($0) : ya.contains($0) }.joined()
        if nuevo.isEmpty { return }
        dias = nuevo.count == 7 ? nil : nuevo
    }

    /// Las opciones de "cuándo": las de la API, con "a una hora" y el despertador primero.
    static func cuandos(_ api: [String]) -> [String] {
        var l = ["hora", "despertador"]
        for k in api where !l.contains(k) { l.append(k) }
        return l
    }

    static func nueva(ahora: Date = Date()) -> Automatizacion {
        Automatizacion(id: "a" + String(Int(ahora.timeIntervalSince1970 * 1000), radix: 36), activa: true, cuando: "recordatorio",
                       hacer: [AccionAuto(tipo: "telegram", texto: "{robot}: {texto}")])
    }
}

struct Ejecucion: Identifiable {
    let id = UUID()
    let evento: String, accion: String, ok: Bool, detalle: String, en: Date?
}

struct ClienteMCP: Identifiable, Equatable {
    let id: String
    let cliente: String
    let usada: Date?
}

struct EstadoTelegram: Equatable {
    var activo = false
    var bot = ""
    var vinculado = false
    var nombre = ""
}

let NOMBRES_CUANDO: [String: String] = [
    "hora": "A una hora", "despertador": "Suena el despertador", "juego": "Termina un juego", "animo": "Te pregunta cómo estás",
    "bicho-cerca": "Otro robot cerca",
    "recordatorio": "Muestra un recordatorio", "pomodoro": "Termina un pomodoro", "bateria-baja": "Poca batería",
    "desconectado": "Se desconecta", "conectado": "Se conecta", "despierta": "Se despierta", "duerme": "Se duerme", "expresion": "Cambia de cara",
    "tacto": "Lo tocan", "doble-toque": "Doble toque", "caricia": "Una caricia", "muchos-toques": "Muchos toques", "levantado": "Lo levantan",
    "sacudida": "Lo sacuden", "sacudida-suave": "Sacudida suave", "sacudida-fuerte": "Sacudida fuerte", "boca-abajo": "Boca abajo",
    "inclinado": "Lo inclinan", "caida": "Se cae", "voz": "Le hablan", "nombre": "Dicen su nombre", "ruido": "Un ruido fuerte", "musica": "Música",
    "cargando": "Lo enchufan", "desenchufado": "Lo desenchufan", "cargado": "Carga completa", "volvio": "Volvés", "hito": "Un hito",
]

extension ApiSintetica {
    /// Un pedido con el cuerpo tal cual (JSON crudo o binario). Devuelve los bytes.
    func pedirCrudo(_ ruta: String, _ metodo: String, cuerpo: Data? = nil, tipo: String = "application/json") async throws -> Data {
        var r = try pedido(ruta, metodo)
        if let cuerpo {
            r.httpBody = cuerpo
            r.setValue(tipo, forHTTPHeaderField: "Content-Type")
        }
        let (datos, resp): (Data, URLResponse)
        do { (datos, resp) = try await URLSession.shared.data(for: r) } catch {
            throw ErrorApi(estado: 0, mensaje: "Sin conexión con el servidor.", detalle: "")
        }
        let estado = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if estado >= 400 {
            let obj = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] ?? [:]
            throw ErrorApi(estado: estado, mensaje: obj["error"] as? String ?? "Error \(estado)", detalle: obj["detalle"] as? String ?? "")
        }
        return datos
    }

    func robots() async throws -> [RobotNube] {
        ((try await pedir("/v1/bichos"))["bichos"] as? [[String: Any]] ?? []).map { RobotNube($0) }
    }

    func robot(_ id: String) async throws -> RobotNube { RobotNube(try await pedir("/v1/bichos/\(id)")) }

    /// La config: su versión y el texto JSON.
    func config(_ id: String) async throws -> (version: Int, texto: String) {
        let o = try await pedir("/v1/bichos/\(id)/config")
        let c = o["config"] as? [String: Any] ?? ["version": 1]
        return ((o["version"] as? NSNumber)?.intValue ?? 0, ConfigDoc(c).texto)
    }

    /// La guarda (la API la valida con el mismo núcleo). Devuelve la versión nueva.
    @discardableResult
    func guardarConfig(_ id: String, _ texto: String) async throws -> Int {
        let d = try await pedirCrudo("/v1/bichos/\(id)/config", "PUT", cuerpo: Data(texto.utf8))
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        return (o["version"] as? NSNumber)?.intValue ?? 0
    }

    /// expresion, nombre, evento o reproducir.
    func comando(_ id: String, _ c: [String: String]) async throws { _ = try await pedir("/v1/bichos/\(id)/comando", "POST", c) }

    func imagenes(_ id: String) async throws -> [EspacioImagen] {
        ((try await pedir("/v1/bichos/\(id)/imagenes"))["imagenes"] as? [[String: Any]] ?? []).compactMap { o in
            guard let e = (o["espacio"] as? NSNumber)?.intValue else { return nil }
            return EspacioImagen(espacio: e, largo: (o["largo"] as? NSNumber)?.uint32Value ?? 0, crc: (o["crc"] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    func imagen(_ id: String, _ espacio: Int) async throws -> [UInt8] {
        [UInt8](try await pedirCrudo("/v1/bichos/\(id)/imagenes/\(espacio)", "GET"))
    }

    func subirImagen(_ id: String, _ espacio: Int, _ qoi: [UInt8]) async throws {
        _ = try await pedirCrudo("/v1/bichos/\(id)/imagenes/\(espacio)", "PUT", cuerpo: Data(qoi), tipo: "application/octet-stream")
    }

    func borrarImagen(_ id: String, _ espacio: Int) async throws { _ = try await pedirCrudo("/v1/bichos/\(id)/imagenes/\(espacio)", "DELETE") }

    func ponerApodo(_ id: String, _ apodo: String) async throws -> String {
        (try await pedir("/v1/bichos/\(id)", "PATCH", ["apodo": apodo]))["apodo"] as? String ?? apodo
    }

    func quitar(_ id: String) async throws { _ = try await pedirCrudo("/v1/bichos/\(id)", "DELETE") }

    func telegram() async throws -> EstadoTelegram {
        let o = try await pedir("/v1/telegram")
        return EstadoTelegram(activo: o["activo"] as? Bool ?? false, bot: o["bot"] as? String ?? "",
                              vinculado: o["vinculado"] as? Bool ?? false, nombre: o["nombre"] as? String ?? "")
    }

    /// Un link de un solo uso al bot (t.me/…?start=…).
    func vincularTelegram() async throws -> String? { (try await pedir("/v1/telegram/vincular", "POST"))["enlace"] as? String }
    func desvincularTelegram() async throws { _ = try await pedir("/v1/telegram", "DELETE") }

    func automatizaciones(_ id: String) async throws -> (lista: [Automatizacion], historial: [Ejecucion], cuandos: [String]) {
        let d = try await pedirCrudo("/v1/bichos/\(id)/automatizaciones", "GET")
        return Self.leerAutomatizaciones(d)
    }

    func guardarAutomatizaciones(_ id: String, _ l: [Automatizacion]) async throws -> (lista: [Automatizacion], historial: [Ejecucion], cuandos: [String]) {
        let cuerpo = try JSONEncoder().encode(["automatizaciones": l])
        return Self.leerAutomatizaciones(try await pedirCrudo("/v1/bichos/\(id)/automatizaciones", "PUT", cuerpo: cuerpo))
    }

    static func leerAutomatizaciones(_ d: Data) -> (lista: [Automatizacion], historial: [Ejecucion], cuandos: [String]) {
        struct Respuesta: Decodable { var automatizaciones: [Automatizacion]? }
        let lista = (try? JSONDecoder().decode(Respuesta.self, from: d))?.automatizaciones ?? []
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        let historial = (o["historial"] as? [[String: Any]] ?? []).map { h in
            Ejecucion(evento: h["evento"] as? String ?? "", accion: h["accion"] as? String ?? "", ok: h["ok"] as? Bool ?? false,
                      detalle: h["detalle"] as? String ?? "", en: (h["en"] as? String).flatMap(fechaISO))
        }
        return (lista, historial, o["cuandos"] as? [String] ?? [])
    }

    func probarAutomatizacion(_ id: String, _ n: Int) async throws { _ = try await pedir("/v1/bichos/\(id)/automatizaciones/\(n)/probar", "POST") }

    func secretoWebhook(rotar: Bool) async throws -> String {
        (try await pedir("/v1/webhooks/secreto", rotar ? "POST" : "GET"))["secreto"] as? String ?? ""
    }

    /// Las IAs conectadas por MCP (OAuth) y la URL del conector.
    func clientesMCP() async throws -> (clientes: [ClienteMCP], url: String) {
        let o = try await pedir("/v1/mcp/clientes")
        let l: [[String: Any]] = o["clientes"] as? [[String: Any]] ?? []
        let clientes: [ClienteMCP] = l.map { c in
            ClienteMCP(id: c["id"] as? String ?? "", cliente: c["cliente"] as? String ?? "IA",
                       usada: (c["usada"] as? String).flatMap(fechaISO))
        }
        return (clientes, o["url"] as? String ?? "")
    }

    func desconectarMCP(_ id: String) async throws { _ = try await pedirCrudo("/v1/mcp/clientes/\(id)", "DELETE") }

    /// Los eventos en vivo de toda la cuenta (SSE /v1/eventos).
    func eventosCuenta() -> AsyncThrowingStream<EventoNube, Error> {
        AsyncThrowingStream { cont in
            let tarea = Task {
                do {
                    var r = try pedido("/v1/eventos")
                    r.timeoutInterval = 3600
                    r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await URLSession.shared.bytes(for: r)
                    let estado = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if estado >= 400 { throw ErrorApi(estado: estado, mensaje: "Error \(estado)", detalle: "") }
                    var lector = LectorSSE()
                    for try await linea in bytes.lines {
                        if let e = lector.leer(linea) { cont.yield(e) }
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

/// Lee un flujo SSE renglón por renglón ("event: x", "data: {json}"). Cada
/// data trae {tipo, bicho, datos} (api/internal/eventos).
struct LectorSSE {
    private var tipo = ""

    mutating func leer(_ linea: String) -> EventoNube? {
        if linea.isEmpty { tipo = ""; return nil }
        if linea.hasPrefix(":") { return nil }
        let (campo, valor) = Self.partir(linea)
        if campo == "event" { tipo = valor; return nil }
        guard campo == "data", let o = (try? JSONSerialization.jsonObject(with: Data(valor.utf8))) as? [String: Any] else { return nil }
        let t = o["tipo"] as? String ?? tipo
        tipo = ""
        return EventoNube(tipo: t, datos: o["datos"] as? [String: Any] ?? [:], bicho: (o["bicho"] as? String ?? "").uppercased())
    }

    private static func partir(_ l: String) -> (String, String) {
        guard let i = l.firstIndex(of: ":") else { return (l, "") }
        var v = l[l.index(after: i)...]
        if v.hasPrefix(" ") { v = v.dropFirst() }
        return (String(l[..<i]), String(v))
    }
}

/// Lo que el robot avisa solo con un registro cortito: un recordatorio (por su
/// índice en la config) o el fin de una tanda de pomodoro (evento 32). Igual
/// que web/src/lib/bicho.svelte.ts.
enum AvisoRobot: Equatable {
    case recordatorio(Int), pomodoro, despertador
    /// Terminó una partida: el juego (0 a 4) y el resultado (0 perdiste, 1 ganaste, 2 empate, 3 sin resultado).
    case juego(Int, Int)
    /// Respondió el "¿cómo estás?": 0 bien, 1 más o menos, 2 mal.
    case animo(Int)
}

func avisosDeMarco(car: Int, _ b: [UInt8]) -> [AvisoRobot] {
    guard car == Car.comando.rawValue, b.count >= 3, b[0] == 0x9E, b[1] == 0, b[2] <= 2 else { return [] }
    var l: [AvisoRobot] = []
    for k in 0 ..< Int(b[2]) {
        let i = 3 + k * 6
        guard i + 6 <= b.count else { break }
        let tipo = b[i + 4], dato = b[i + 5]
        switch (tipo, dato) {
        case (4, _): l.append(.recordatorio(Int(dato)))
        case (5, _): l.append(.juego(Int(dato) / 16, Int(dato) % 16))
        case (6, _): l.append(.animo(Int(dato)))
        case (0, 32): l.append(.pomodoro)
        case (0, 33): l.append(.despertador)
        default: break
        }
    }
    return l
}
