import Foundation

/// Lo que la app deja editar de la configuración (shared/formato/config.schema.json).
struct Ajustes: Equatable {
    var nombre = "bicho"
    var colorOjos: String? = nil   // "#RRGGBB"; nil = el naranja de la marca
    var tamano: Double = 1         // 0,5 a 1,5
    // La personalidad: seis rasgos de 0 a 1 (config v2).
    var energia: Double = 0.5
    var sociabilidad: Double = 0.5
    var picardia: Double = 0.45
    var timidez: Double = 0.3
    var curiosidad: Double = 0.55
    var malGenio: Double = 0.25
    var preset: String? = nil
    // El horario: se duerme a suenoDesde y se despierta a suenoHasta ("HH:MM"); nil = el de fábrica.
    var suenoDesde: String? = nil
    var suenoHasta: String? = nil
    var lista: [String] = []        // "cara:<nombre>" o "imagen:<0-7>"
    var rotar = 0                   // minutos; 0 = no rota
}

/// Lee y escribe los ajustes sobre el JSON completo de la config, sin tocar lo
/// que la app no edita (expresiones propias, reglas, modo).
enum EditorConfig {
    private static func objeto(_ texto: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(texto.utf8))) as? [String: Any] ?? [:]
    }

    static func leer(_ texto: String) -> Ajustes {
        let raiz = objeto(texto)
        let cara = raiz["cara"] as? [String: Any] ?? [:]
        let per = raiz["personalidad"] as? [String: Any] ?? [:]
        // v2: horario {despierta, duerme}; v1: personalidad.sueno "HH:MM-HH:MM" (cuándo duerme).
        let horario = raiz["horario"] as? [String: Any]
        let sueno = (per["sueno"] as? String)?.split(separator: "-").map(String.init)
            ?? horario.map { [($0["duerme"] as? String) ?? "23:30", ($0["despierta"] as? String) ?? "08:00"] }
        let rasgo = { (n: String, d: Double) in (per[n] as? NSNumber)?.doubleValue ?? d }
        return Ajustes(
            nombre: raiz["nombre"] as? String ?? "bicho",
            colorOjos: cara["color"] as? String,
            tamano: (cara["tamano"] as? NSNumber)?.doubleValue ?? 1,
            energia: rasgo("energia", 0.5), sociabilidad: rasgo("sociabilidad", 0.5), picardia: rasgo("picardia", 0.45),
            timidez: rasgo("timidez", 0.3), curiosidad: rasgo("curiosidad", 0.55), malGenio: rasgo("malGenio", 0.25),
            preset: per["preset"] as? String,
            suenoDesde: sueno?.first, suenoHasta: sueno?.dropFirst().first,
            lista: raiz["lista"] as? [String] ?? [],
            rotar: (raiz["rotar"] as? NSNumber)?.intValue ?? 0
        )
    }

    static func escribir(_ texto: String, _ a: Ajustes) -> String {
        var raiz = objeto(texto)
        let redondo = { (d: Double) in (d * 100).rounded() / 100 }
        raiz["version"] = 2
        raiz["nombre"] = a.nombre
        var cara = raiz["cara"] as? [String: Any] ?? [:]
        if let c = a.colorOjos { cara["color"] = c } else { cara.removeValue(forKey: "color") }
        cara["tamano"] = redondo(a.tamano)
        raiz["cara"] = cara
        var per = raiz["personalidad"] as? [String: Any] ?? [:]
        per["energia"] = redondo(a.energia)
        per["sociabilidad"] = redondo(a.sociabilidad)
        per["picardia"] = redondo(a.picardia)
        per["timidez"] = redondo(a.timidez)
        per["curiosidad"] = redondo(a.curiosidad)
        per["malGenio"] = redondo(a.malGenio)
        if let p = a.preset { per["preset"] = p } else { per.removeValue(forKey: "preset") }
        per.removeValue(forKey: "sueno")
        raiz["personalidad"] = per
        if let d = a.suenoDesde, let h = a.suenoHasta { raiz["horario"] = ["despierta": h, "duerme": d] } else { raiz.removeValue(forKey: "horario") }
        raiz["lista"] = a.lista
        raiz["rotar"] = a.rotar
        let datos = (try? JSONSerialization.data(withJSONObject: raiz, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"version\":1}".utf8)
        return String(decoding: datos, as: UTF8.self)
    }

    static func hhmmValido(_ s: String) -> Bool { s.wholeMatch(of: #/([01][0-9]|2[0-3]):[0-5][0-9]/#) != nil }

    /// Los presets de shared/formato/vida/personalidades.json (los mismos que la web y el bicho).
    static let presets: [(clave: String, nombre: String, rasgos: [Double])] = [
        ("equilibrado", "Equilibrado", [0.5, 0.5, 0.45, 0.3, 0.55, 0.25]),
        ("timido", "Tímido", [0.4, 0.35, 0.2, 0.9, 0.5, 0.15]),
        ("picaro", "Pícaro", [0.65, 0.6, 0.95, 0.15, 0.6, 0.3]),
        ("dormilon", "Dormilón", [0.15, 0.45, 0.3, 0.35, 0.3, 0.3]),
        ("carinoso", "Cariñoso", [0.5, 0.95, 0.4, 0.3, 0.45, 0.05]),
        ("curioso", "Curioso", [0.65, 0.5, 0.45, 0.2, 0.95, 0.2]),
        ("grunon", "Gruñón", [0.45, 0.25, 0.3, 0.2, 0.35, 0.9]),
        ("electrico", "Eléctrico", [0.95, 0.7, 0.65, 0.1, 0.75, 0.35]),
    ]

    static func conPreset(_ a: Ajustes, _ clave: String) -> Ajustes {
        guard let p = presets.first(where: { $0.clave == clave }) else { return a }
        var b = a
        b.energia = p.rasgos[0]; b.sociabilidad = p.rasgos[1]; b.picardia = p.rasgos[2]
        b.timidez = p.rasgos[3]; b.curiosidad = p.rasgos[4]; b.malGenio = p.rasgos[5]
        b.preset = clave
        return b
    }
}
