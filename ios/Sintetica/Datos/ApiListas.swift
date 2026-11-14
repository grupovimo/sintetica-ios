import Foundation

/// Lo que contestó la S1 en la charla, con la cara y lo que hizo (si hizo algo).
struct RespuestaCharla: Equatable, Sendable {
    var texto = ""
    var expresion = ""
    var quedan = -1
    var origen = "motor"
    /// Lo que hizo ("alarma", "recordatorio", "timer"…); vacío si solo charló.
    var accion = ""
    var enviado = false
    var guardado = false

    init(_ o: [String: Any]) {
        texto = o["texto"] as? String ?? ""
        expresion = o["expresion"] as? String ?? ""
        quedan = (o["quedan"] as? NSNumber)?.intValue ?? -1
        origen = o["origen"] as? String ?? "motor"
        let a = o["accion"] as? String ?? ""
        accion = a == "ninguna" ? "" : a
        enviado = o["enviado"] as? Bool ?? false
        guardado = o["guardado"] as? Bool ?? false
    }
}

/// Un renglón de una lista (de la cuenta, no del robot).
struct ItemLista: Identifiable, Equatable, Sendable {
    let id: String
    var texto: String
    var hecho: Bool

    init(_ o: [String: Any]) {
        id = o["id"] as? String ?? UUID().uuidString
        texto = o["texto"] as? String ?? ""
        hecho = o["hecho"] as? Bool ?? false
    }
}

/// Una lista: la del súper, pendientes o la que sea (GET /v1/listas).
struct ListaNube: Identifiable, Equatable, Sendable {
    let id: String
    var nombre: String
    var items: [ItemLista]

    init(_ o: [String: Any]) {
        id = o["id"] as? String ?? ""
        nombre = o["nombre"] as? String ?? ""
        items = (o["items"] as? [[String: Any]] ?? []).map(ItemLista.init)
    }
}

extension ApiSintetica {
    /// La charla con todo lo que devuelve la nube (texto, expresión y acción).
    func charlarDetalle(_ id: String, _ texto: String) async throws -> RespuestaCharla {
        RespuestaCharla(try await pedir("/v1/bichos/\(id)/charla", "POST", ["texto": texto]))
    }

    // --- Listas (web/src/lib/consola/modulos/Listas.svelte) ---
    func listas() async throws -> (listas: [ListaNube], porDefecto: String) {
        let o = try await pedir("/v1/listas")
        return ((o["listas"] as? [[String: Any]] ?? []).map(ListaNube.init), o["porDefecto"] as? String ?? "súper")
    }

    func crearLista(_ nombre: String) async throws -> ListaNube {
        ListaNube(try await pedir("/v1/listas", "POST", ["nombre": nombre]))
    }

    func borrarLista(_ id: String) async throws { _ = try await pedir("/v1/listas/\(id)", "DELETE") }

    func agregarALista(_ id: String, _ texto: String) async throws -> ListaNube {
        ListaNube((try await pedir("/v1/listas/\(id)/items", "POST", ["texto": texto]))["lista"] as? [String: Any] ?? [:])
    }

    func tacharEnLista(_ id: String, item: String, hecho: Bool) async throws {
        _ = try await pedir("/v1/listas/\(id)/items/\(item)", "PATCH", ["hecho": hecho])
    }

    func sacarDeLista(_ id: String, item: String) async throws { _ = try await pedir("/v1/listas/\(id)/items/\(item)", "DELETE") }

    func limpiarLista(_ id: String) async throws -> ListaNube {
        ListaNube((try await pedir("/v1/listas/\(id)/limpiar", "POST", [:]))["lista"] as? [String: Any] ?? [:])
    }
}
