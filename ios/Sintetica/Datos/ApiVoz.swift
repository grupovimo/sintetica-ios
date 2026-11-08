import Foundation

// Entrar con Telegram, la voz (ElevenLabs y la gratis), el paquete sin
// internet, la IA propia y la conversación en tiempo real (docs/nube.md).

struct MetodosSesion: Equatable { var email: Bool, telegram: Bool, bot: String }

/// Un pedido de entrada con Telegram: el link al bot y el secreto que solo tiene esta app.
struct EntradaTelegram: Equatable { let token: String, enlace: String, secreto: String }

enum RespuestaEntrada: Equatable { case pendiente, confirmar, adentro(String), vencio }

struct VozEdge: Equatable {
    struct Voz: Equatable, Identifiable { let id: String, nombre: String, idioma: String }
    var disponible = false, prendida = false
    var voz = ""
    var voces: [Voz] = []
    var usadosHoy = 0, tope = 0

    init(_ o: [String: Any]) {
        disponible = o["disponible"] as? Bool ?? false
        prendida = o["prendida"] as? Bool ?? false
        voz = o["voz"] as? String ?? ""
        voces = (o["voces"] as? [[String: Any]] ?? []).map { v in
            Voz(id: v["id"] as? String ?? "", nombre: v["nombre"] as? String ?? "", idioma: v["idioma"] as? String ?? "")
        }
        usadosHoy = (o["usados_hoy"] as? NSNumber)?.intValue ?? 0
        tope = (o["tope"] as? NSNumber)?.intValue ?? 0
    }
}

/// "Elena · AR": el primer nombre y el país.
func nombreVozEdge(_ v: VozEdge.Voz) -> String {
    let primero = v.nombre.split(separator: " ").first.map(String.init) ?? v.nombre
    let pais = v.idioma.count > 3 ? String(v.idioma.dropFirst(3)) : v.idioma
    return "\(primero) · \(pais)"
}

struct VozEleven: Equatable {
    struct Voz: Equatable, Identifiable { let id: String, nombre: String }
    var conectado = false
    var voz = "", vozNombre = ""
    var voces: [Voz] = []
    var leer = false
    var usadosHoy = 0, tope = 5000
    var segundosHoy = 0, topeMinutos = 10

    init(_ o: [String: Any]) {
        conectado = o["conectado"] as? Bool ?? false
        voz = o["voz"] as? String ?? ""
        vozNombre = o["voz_nombre"] as? String ?? ""
        voces = (o["voces"] as? [[String: Any]] ?? []).map { Voz(id: $0["id"] as? String ?? "", nombre: $0["nombre"] as? String ?? "") }
        leer = o["leer"] as? Bool ?? false
        usadosHoy = (o["usados_hoy"] as? NSNumber)?.intValue ?? 0
        tope = (o["tope"] as? NSNumber)?.intValue ?? 5000
        segundosHoy = (o["segundos_hoy"] as? NSNumber)?.intValue ?? 0
        topeMinutos = (o["tope_minutos"] as? NSNumber)?.intValue ?? 10
    }
}

/// Los topes van en escalones (una perilla de 0 a 200 000 de a uno no se puede girar).
let ESCALONES_LETRAS = [0, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000]
let ESCALONES_MINUTOS = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 240]
let ESCALONES_IA = [0, 10, 20, 30, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
/// El escalón más cercano a v.
func escalon(_ l: [Int], _ v: Int) -> Int {
    var m = 0
    for (i, x) in l.enumerated() where abs(x - v) < abs(l[m] - v) { m = i }
    return m
}

/// 1500 → "1,5 k"; 200000 → "200 k".
func miles(_ n: Int) -> String {
    guard n >= 1000 else { return String(n) }
    let v = Double(n) / 1000
    let t = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    return "\(t) k"
}

func megas(_ b: Int) -> String {
    let v = Double(b) / 1_048_576
    return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: ",0", with: "")
}

struct PaqueteVoz: Equatable {
    var estado = "nuevo"  // nuevo, generando, listo, parcial, error
    var error = ""
    var version = 0
    var voz = "", vozNueva = "", proveedor = ""
    var frases = 0, bytes = 0, total = 0, faltan = 0, gasta = 0, bytesEstimados = 0
    var disponible = false
    var hechas = 0, de = 0

    init(_ o: [String: Any]) {
        func n(_ k: String) -> Int { (o[k] as? NSNumber)?.intValue ?? 0 }
        estado = o["estado"] as? String ?? "nuevo"
        error = o["error"] as? String ?? ""
        version = n("version")
        voz = o["voz"] as? String ?? ""
        vozNueva = o["voz_nueva"] as? String ?? ""
        proveedor = o["proveedor"] as? String ?? ""
        frases = n("frases"); bytes = n("bytes"); total = n("total"); faltan = n("faltan"); gasta = n("gasta")
        bytesEstimados = n("bytes_estimados")
        disponible = o["disponible"] as? Bool ?? false
        let p = o["progreso"] as? [String: Any] ?? [:]
        hechas = (p["hechas"] as? NSNumber)?.intValue ?? 0
        de = (p["de"] as? NSNumber)?.intValue ?? 0
    }

    var hay: Bool { version > 0 }
    var cambio: Bool { hay && (faltan > 0 || (!vozNueva.isEmpty && vozNueva != voz)) }
    var etiqueta: String {
        ["listo": "Listo", "parcial": "A medias", "generando": "Grabando", "nuevo": "Sin paquete", "error": "Falló"][estado] ?? estado
    }
}

struct IAPropia: Equatable {
    var propia = false, servidor = false
    var proveedor = "", modelo = "", urlPista = ""
    var usadasHoy = 0, tope = 0
    init(_ o: [String: Any]) {
        propia = o["propia"] as? Bool ?? false
        servidor = o["servidor"] as? Bool ?? false
        proveedor = o["proveedor"] as? String ?? ""
        modelo = o["modelo"] as? String ?? ""
        urlPista = o["url_pista"] as? String ?? ""
        usadasHoy = (o["usadas_hoy"] as? NSNumber)?.intValue ?? 0
        tope = (o["tope"] as? NSNumber)?.intValue ?? 0
    }
    /// Cuál está usando: la tuya, la del servidor o ninguna (el motor propio).
    var cual: String { propia ? "tuya" : servidor ? "servidor" : "ninguna" }
}

/// Los servicios conocidos: completan la URL y sugieren un modelo.
struct ServicioIA: Equatable { let clave, nombre, proveedor, url, modelo, claves: String }
let SERVICIOS_IA: [ServicioIA] = [
    ServicioIA(clave: "anthropic", nombre: "Anthropic", proveedor: "anthropic", url: "", modelo: "claude-haiku-5-5", claves: "https://console.anthropic.com/settings/keys"),
    ServicioIA(clave: "groq", nombre: "Groq", proveedor: "compatible", url: "https://api.groq.com/openai/v1", modelo: "llama-3.3-70b-versatile", claves: "https://console.groq.com/keys"),
    ServicioIA(clave: "openrouter", nombre: "OpenRouter", proveedor: "compatible", url: "https://openrouter.ai/api/v1", modelo: "meta-llama/llama-3.3-70b-instruct", claves: "https://openrouter.ai/keys"),
    ServicioIA(clave: "gemini", nombre: "Gemini", proveedor: "compatible", url: "https://generativelanguage.googleapis.com/v1beta/openai", modelo: "gemini-2.5-flash", claves: "https://aistudio.google.com/apikey"),
    ServicioIA(clave: "otro", nombre: "Otro", proveedor: "compatible", url: "", modelo: "", claves: ""),
]

/// El nombre del servicio de una IA propia (por la pista de su URL).
func servicioDe(_ ia: IAPropia) -> String {
    if ia.proveedor == "anthropic" { return "Anthropic" }
    if !ia.urlPista.isEmpty, let s = SERVICIOS_IA.first(where: { !$0.url.isEmpty && $0.url.contains(ia.urlPista) }) { return s.nombre }
    return ia.urlPista.isEmpty ? "Compatible" : ia.urlPista
}

/// Para hablar en tiempo real: la URL firmada y lo que dura.
struct PedidoConversacion: Equatable { let url: String, segundos: Int, quedan: Int, expresiones: [String] }

extension ApiSintetica {
    /// Un pedido que devuelve el estado y el JSON aunque sea un error (el 409 del paquete trae el estado).
    func pedirConEstado(_ ruta: String, _ metodo: String, _ cuerpo: [String: Any]) async throws -> (Int, [String: Any]) {
        let r = try pedido(ruta, metodo, cuerpo)
        let (d, resp): (Data, URLResponse)
        do { (d, resp) = try await URLSession.shared.data(for: r) } catch { throw ErrorApi(estado: 0, mensaje: "Sin conexión con el servidor.", detalle: "") }
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, o)
    }

    // --- Entrar ---
    func metodos() async throws -> MetodosSesion {
        let o = try await pedir("/v1/sesion/metodos")
        return MetodosSesion(email: o["email"] as? Bool ?? false, telegram: o["telegram"] as? Bool ?? false, bot: o["bot"] as? String ?? "")
    }

    func pedirEntradaTelegram() async throws -> EntradaTelegram {
        let o = try await pedir("/v1/sesion/telegram", "POST", ["cliente": "app"])
        return EntradaTelegram(token: o["token"] as? String ?? "", enlace: o["enlace"] as? String ?? "", secreto: o["secreto"] as? String ?? "")
    }

    /// Espera hasta 25 s a que toquen Start (y Crear mi cuenta) en el bot.
    func esperarEntradaTelegram(_ e: EntradaTelegram) async throws -> RespuestaEntrada {
        let t = e.token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? e.token
        do {
            let o = try await pedir("/v1/sesion/telegram/\(t)?esperar=25", encabezados: ["X-Sintetica-Secreto": e.secreto])
            return Self.leerEntrada(o)
        } catch let x as ErrorApi where x.estado == 410 || x.estado == 401 {
            return .vencio
        }
    }

    static func leerEntrada(_ o: [String: Any]) -> RespuestaEntrada {
        if let t = o["token"] as? String, !t.isEmpty { return .adentro(t) }
        return o["estado"] as? String == "confirmar" ? .confirmar : .pendiente
    }

    /// El código de 6 dígitos del bot ("123 456" o "123456"). Devuelve el token de la sesión.
    func codigoEntradaTelegram(_ e: EntradaTelegram, _ codigo: String) async throws -> String {
        let t = e.token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? e.token
        let o = try await pedir("/v1/sesion/telegram/\(t)/codigo", "POST", ["codigo": codigo], encabezados: ["X-Sintetica-Secreto": e.secreto])
        guard let s = o["token"] as? String, !s.isEmpty else { throw ErrorApi(estado: 0, mensaje: "No vino la sesión.", detalle: "") }
        return s
    }

    // --- Voz ---
    /// Un PUT o DELETE que devuelve el JSON de la respuesta.
    func pedirJSON(_ ruta: String, _ metodo: String, _ cuerpo: [String: Any]? = nil) async throws -> [String: Any] {
        let datos: Data? = try cuerpo.map { try JSONSerialization.data(withJSONObject: $0) }
        let d = try await pedirCrudo(ruta, metodo, cuerpo: datos)
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    func vozEdge() async throws -> VozEdge { VozEdge(try await pedir("/v1/voz/edge")) }
    func ponerVozEdge(_ c: [String: Any]) async throws -> VozEdge { VozEdge(try await pedirJSON("/v1/voz/edge", "PUT", c)) }
    func vozEleven() async throws -> VozEleven { VozEleven(try await pedir("/v1/voz/elevenlabs")) }
    func ponerVozEleven(_ c: [String: Any]) async throws -> VozEleven { VozEleven(try await pedirJSON("/v1/voz/elevenlabs", "PUT", c)) }
    func sacarVozEleven() async throws -> VozEleven { VozEleven(try await pedirJSON("/v1/voz/elevenlabs", "DELETE")) }
    /// El mp3 de una prueba ("edge" o "elevenlabs").
    func probarVoz(_ cual: String, texto: String) async throws -> Data {
        let c = try JSONSerialization.data(withJSONObject: ["texto": texto])
        return try await pedirCrudo("/v1/voz/\(cual)/probar", "POST", cuerpo: c)
    }

    func paqueteVoz(_ id: String) async throws -> PaqueteVoz { PaqueteVoz(try await pedir("/v1/bichos/\(id)/voz/paquete")) }

    /// Lo pide; con ElevenLabs y algo que gastar, sin confirmar vuelve el estado para mostrar cuánto (el 409).
    func generarPaqueteVoz(_ id: String, confirmar: Bool) async throws -> (paquete: PaqueteVoz, confirmar: Bool) {
        let (s, o) = try await pedirConEstado("/v1/bichos/\(id)/voz/paquete", "POST", confirmar ? ["confirmar": true] : [:])
        if s == 409, o["estado"] != nil { return (PaqueteVoz(o), true) }
        if s >= 400 { throw ErrorApi(estado: s, mensaje: o["error"] as? String ?? "Error \(s)", detalle: o["detalle"] as? String ?? "") }
        return (PaqueteVoz(o), false)
    }

    // --- IA propia ---
    func iaPropia() async throws -> IAPropia { IAPropia(try await pedir("/v1/ia")) }
    func ponerIA(_ c: [String: Any]) async throws -> IAPropia { IAPropia(try await pedirJSON("/v1/ia", "PUT", c)) }
    func borrarIA() async throws { _ = try await pedirCrudo("/v1/ia", "DELETE") }

    // --- Conversación ---
    func conversacion(_ id: String) async throws -> PedidoConversacion {
        let o = try await pedir("/v1/bichos/\(id)/conversacion")
        return PedidoConversacion(url: o["url"] as? String ?? "", segundos: (o["segundos"] as? NSNumber)?.intValue ?? 60,
                                  quedan: (o["quedan"] as? NSNumber)?.intValue ?? 0, expresiones: o["expresiones"] as? [String] ?? [])
    }
}
