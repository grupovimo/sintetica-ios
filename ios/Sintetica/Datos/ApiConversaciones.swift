import Foundation

// Las conversaciones que graba el broche (o el celu): la nube las pasa a texto
// y las resume (api/internal/servidor/conversaciones.go).

/// Una conversación grabada (GET /v1/conversaciones). La transcripción viene
/// solo al pedir una (GET /v1/conversaciones/{id}).
struct ConversacionGrabada: Identifiable, Hashable {
    var id = 0
    var bicho = ""
    var empezo: Date?
    var segundos = 0
    /// grabando | procesando | lista | fallo
    var estado = "grabando"
    var titulo = ""
    var resumen = ""
    var puntos: [String] = []
    var pendientes: [String] = []
    var transcripcion = ""
    var detalle = ""

    init(_ o: [String: Any]) {
        id = (o["id"] as? NSNumber)?.intValue ?? 0
        bicho = o["bicho"] as? String ?? ""
        empezo = (o["empezo"] as? String).flatMap(fechaISO)
        segundos = (o["segundos"] as? NSNumber)?.intValue ?? 0
        estado = o["estado"] as? String ?? "grabando"
        titulo = o["titulo"] as? String ?? ""
        resumen = o["resumen"] as? String ?? ""
        puntos = o["puntos"] as? [String] ?? []
        pendientes = o["pendientes"] as? [String] ?? []
        transcripcion = o["transcripcion"] as? String ?? ""
        detalle = o["detalle"] as? String ?? ""
    }

    var lista: Bool { estado == "lista" }
    var fallo: Bool { estado == "fallo" }
    var enCurso: Bool { estado == "grabando" || estado == "procesando" }

    /// El resumen para compartir: título, resumen, puntos y pendientes.
    var textoParaCompartir: String {
        var partes: [String] = []
        if !titulo.isEmpty { partes.append(titulo) }
        if !resumen.isEmpty { partes.append(resumen) }
        if !puntos.isEmpty { partes.append(puntos.map { "• " + $0 }.joined(separator: "\n")) }
        if !pendientes.isEmpty { partes.append("Pendientes:\n" + pendientes.map { "☐ " + $0 }.joined(separator: "\n")) }
        return partes.joined(separator: "\n\n")
    }
}

extension ApiSintetica {
    /// Las últimas (sin la transcripción).
    func conversaciones() async throws -> [ConversacionGrabada] {
        ((try await pedir("/v1/conversaciones"))["conversaciones"] as? [[String: Any]] ?? []).map(ConversacionGrabada.init)
    }

    /// Una, con la transcripción.
    func verConversacion(_ id: Int) async throws -> ConversacionGrabada {
        ConversacionGrabada(try await pedir("/v1/conversaciones/\(id)"))
    }

    /// Empieza una grabación (queda "grabando"). Sin robot: la graba el celu.
    func crearConversacion(bicho: String = "", empezo: Date? = nil) async throws -> ConversacionGrabada {
        var c: [String: Any] = [:]
        if !bicho.isEmpty { c["bicho"] = bicho }
        if let empezo { c["empezo"] = ISO8601DateFormatter().string(from: empezo) }
        return ConversacionGrabada(try await pedir("/v1/conversaciones", "POST", c))
    }

    /// Un trozo del audio, crudo: [u8 formato][…] (hasta 64 KB). Índices desde 0.
    func subirTrozo(_ id: Int, indice: Int, _ trozo: Data) async throws {
        _ = try await pedirCrudo("/v1/conversaciones/\(id)/audio/\(indice)", "PUT", cuerpo: trozo, tipo: "application/octet-stream")
    }

    /// No llega más audio: pasa a "procesando" (la nube transcribe y resume).
    @discardableResult
    func terminarConversacion(_ id: Int) async throws -> ConversacionGrabada {
        ConversacionGrabada(try await pedir("/v1/conversaciones/\(id)/terminar", "POST", [:]))
    }

    /// Solo las que fallaron.
    @discardableResult
    func reintentarConversacion(_ id: Int) async throws -> ConversacionGrabada {
        ConversacionGrabada(try await pedir("/v1/conversaciones/\(id)/reintentar", "POST", [:]))
    }

    func borrarConversacion(_ id: Int) async throws {
        _ = try await pedir("/v1/conversaciones/\(id)", "DELETE")
    }
}
