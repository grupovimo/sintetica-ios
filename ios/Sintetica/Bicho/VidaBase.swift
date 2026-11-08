import Foundation

/// Lo de fábrica del motor de vida (shared/formato/vida, en el bundle): las
/// expresiones paramétricas, los comportamientos y las reglas. Lo mismo que
/// embebe el firmware.
enum VidaBase {
    private static func leer(_ nombre: String) -> Any? {
        guard let url = Bundle.main.url(forResource: nombre, withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    static let expresiones: [String: [String: Any]] = leer("expresiones") as? [String: [String: Any]] ?? [:]
    static let comportamientos: [String: [String: Any]] = leer("comportamientos") as? [String: [String: Any]] ?? [:]
    static let reglas: [Regla] = (leer("reglas") as? [[String: Any]] ?? []).compactMap { Regla($0) }

    /// En el orden del archivo (JSONSerialization no lo guarda): primero las de siempre.
    static let ordenCaras = ["neutral", "contento", "emocionado", "risa", "sospecha", "sorpresa", "miedo", "dormido", "bostezo", "enojado",
                             "grunon", "triste", "verguenza", "guino", "enamorado", "mareado", "escuchando", "hablando", "pensando",
                             "confundido", "curioso", "aburrido", "orgulloso", "concentrado", "bateria-baja", "cargando", "actualizando",
                             "sin-conexion", "ko", "glitch", "cansado", "ofendido", "estornudo", "espiar", "estirarse", "sonando", "pesadilla"]

    /// Los JSON sueltos del bundle (los dibujos del manual y las animaciones de ejemplo).
    private static let sueltos: [[String: Any]] = {
        var urls: [URL] = []
        for d in ["caras", "animaciones"] { urls += Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: d) ?? [] }
        return urls.compactMap { u in
            guard let d = try? Data(contentsOf: u) else { return nil }
            return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        }
    }()

    /// Los 16 dibujos del manual, en su orden: nombre y documento (formas).
    static let dibujos: [(nombre: String, doc: [String: Any])] = {
        let l = sueltos.filter { $0["formas"] != nil && $0["nombre"] is String }
        let orden = l.sorted { (($0["numero"] as? NSNumber)?.intValue ?? 99) < (($1["numero"] as? NSNumber)?.intValue ?? 99) }
        return orden.map { o in
            var doc: [String: Any] = ["formas": o["formas"] ?? []]
            if let p = o["parpadea"] { doc["parpadea"] = p }
            return (o["nombre"] as? String ?? "", doc)
        }
    }()

    /// Las animaciones de ejemplo.
    static let animaciones: [(nombre: String, doc: [String: Any])] = {
        sueltos.filter { $0["pistas"] != nil && $0["nombre"] is String }.map { o in
            var doc = o
            doc.removeValue(forKey: "nombre")
            return (o["nombre"] as? String ?? "", doc)
        }.sorted { $0.nombre < $1.nombre }
    }()

    static var nombresCaras: [String] {
        ordenCaras.filter { expresiones[$0] != nil } + expresiones.keys.filter { !ordenCaras.contains($0) }.sorted()
    }
}

/// Un parámetro del rostro (firmware/nucleo/rostro.cpp): clave, mínimo, máximo y de fábrica.
struct ParametroRostro: Sendable {
    let clave: String, min: Double, max: Double, defecto: Double
}

let PARAMS_OJO: [ParametroRostro] = [
    .init(clave: "w", min: 0.03, max: 0.2, defecto: 0.105), .init(clave: "h", min: 0.03, max: 0.32, defecto: 0.23),
    .init(clave: "r", min: 0, max: 1, defecto: 1), .init(clave: "tilt", min: -0.6, max: 0.6, defecto: 0),
    .init(clave: "lt", min: 0, max: 0.5, defecto: 0), .init(clave: "lta", min: -0.8, max: 0.8, defecto: 0),
    .init(clave: "lb", min: 0, max: 0.5, defecto: 0), .init(clave: "lba", min: -0.8, max: 0.8, defecto: 0),
    .init(clave: "smile", min: 0, max: 1, defecto: 0), .init(clave: "heart", min: 0, max: 1, defecto: 0),
    .init(clave: "star", min: 0, max: 1, defecto: 0), .init(clave: "cross", min: 0, max: 1, defecto: 0),
    .init(clave: "ring", min: 0, max: 1, defecto: 0), .init(clave: "pupil", min: 0, max: 1, defecto: 0),
    .init(clave: "squash", min: 0.7, max: 1.3, defecto: 1),
]
let PARAMS_CARA: [ParametroRostro] = [
    .init(clave: "gx", min: -0.3, max: 0.3, defecto: 0), .init(clave: "gy", min: -0.25, max: 0.25, defecto: 0),
    .init(clave: "ey", min: -0.25, max: 0.25, defecto: 0), .init(clave: "sep", min: 0.15, max: 0.45, defecto: 0.3),
    .init(clave: "ftilt", min: -0.6, max: 0.6, defecto: 0), .init(clave: "fscale", min: 0.7, max: 1.3, defecto: 1),
    .init(clave: "spin", min: 0, max: 1, defecto: 0), .init(clave: "orbit", min: 0, max: 1, defecto: 0),
    .init(clave: "pulse", min: 0, max: 1, defecto: 0), .init(clave: "beat", min: 0, max: 1, defecto: 0),
    .init(clave: "glitch", min: 0, max: 1, defecto: 0), .init(clave: "dim", min: 0, max: 1, defecto: 0),
    .init(clave: "hue", min: 0, max: 1, defecto: 0), .init(clave: "mo", min: 0, max: 0.2, defecto: 0),
    .init(clave: "mw", min: 0.02, max: 0.2, defecto: 0.07), .init(clave: "mcurve", min: -1, max: 1, defecto: 0),
    .init(clave: "blush", min: 0, max: 1, defecto: 0), .init(clave: "shake", min: 0, max: 1, defecto: 0),
]
let LIMITES_PARAM: [String: (Double, Double)] = {
    var l: [String: (Double, Double)] = [:]
    for p in PARAMS_OJO + PARAMS_CARA { l[p.clave] = (p.min, p.max) }
    return l
}()

let MOVIMIENTOS = ["ninguno", "rebote", "saltitos", "risa", "mirada-lado", "salto", "encogerse", "dormir", "temblor", "resoplido",
                   "lagrima", "achicarse", "picaro", "latido", "bamboleo", "escuchar", "hablar", "pensar", "duda", "acercarse", "suspiro",
                   "quieto", "cabeceo", "carga", "orbita", "buscar", "caer", "glitch", "estirarse"]
let PARTICULAS = ["zzz", "corazon", "lagrima", "gota", "chispa", "pregunta", "exclamacion", "nota", "estrella", "burbuja"]
let PARPADEOS = ["normal", "menos", "mas", "no", "lento", "rapido", "doble"]
let MIRADAS = ["libre", "frente", "arriba", "abajo", "izquierda", "derecha", "lado", "alrededor", "perdida", "reojo", "estimulo", "rem", "ovejas"]
let GLIFO: [String: String] = ["zzz": "z", "corazon": "♥", "lagrima": "💧", "gota": "·", "chispa": "✦", "pregunta": "?",
                               "exclamacion": "!", "nota": "♪", "estrella": "★", "burbuja": "○"]

/// Los valores de una cara: "izq.w", "der.w" para los ojos y "gx" para los globales.
typealias ValoresRostro = [String: Double]

enum Rostro {
    static var neutral: ValoresRostro {
        var v: ValoresRostro = [:]
        for p in PARAMS_OJO { v["izq.\(p.clave)"] = p.defecto; v["der.\(p.clave)"] = p.defecto }
        for p in PARAMS_CARA { v[p.clave] = p.defecto }
        return v
    }

    /// Aplica un documento de expresión encima (como leerCaraVida del núcleo:
    /// primero los globales, después ojo, izq y der).
    static func aplicar(_ doc: [String: Any], a v: inout ValoresRostro) {
        for p in PARAMS_CARA { if let n = (doc[p.clave] as? NSNumber)?.doubleValue { v[p.clave] = n } }
        for (lado, destinos) in [("ojo", ["izq", "der"]), ("izq", ["izq"]), ("der", ["der"])] {
            guard let o = doc[lado] as? [String: Any] else { continue }
            for p in PARAMS_OJO {
                guard let n = (o[p.clave] as? NSNumber)?.doubleValue else { continue }
                for d in destinos { v["\(d).\(p.clave)"] = n }
            }
        }
    }

    /// Los valores de una cara de fábrica (con lo que extienda).
    static func deFabrica(_ nombre: String, profundidad: Int = 0) -> ValoresRostro {
        var v = neutral
        guard let doc = VidaBase.expresiones[nombre], profundidad < 6 else { return v }
        if let ext = doc["extiende"] as? String { v = deFabrica(ext, profundidad: profundidad + 1) }
        aplicar(doc, a: &v)
        return v
    }

    /// Lo que difiere de la referencia, como documento (lo que guarda la web).
    static func documento(_ v: ValoresRostro, referencia r: ValoresRostro) -> [String: Any] {
        var d: [String: Any] = [:]
        let red = { (x: Double) in (x * 1000).rounded() / 1000 }
        let distinto = { (a: Double, z: Double) in abs(a - z) > 0.0005 }
        var ojo: [String: Any] = [:], izq: [String: Any] = [:], der: [String: Any] = [:]
        for p in PARAMS_OJO {
            let a = v["izq.\(p.clave)"] ?? p.defecto, z = v["der.\(p.clave)"] ?? p.defecto
            let ra = r["izq.\(p.clave)"] ?? p.defecto, rz = r["der.\(p.clave)"] ?? p.defecto
            if !distinto(a, z) && (distinto(a, ra) || distinto(z, rz)) {
                ojo[p.clave] = red(a)
            } else {
                if distinto(a, ra) { izq[p.clave] = red(a) }
                if distinto(z, rz) { der[p.clave] = red(z) }
            }
        }
        if !ojo.isEmpty { d["ojo"] = ojo }
        if !izq.isEmpty { d["izq"] = izq }
        if !der.isEmpty { d["der"] = der }
        for p in PARAMS_CARA {
            let a = v[p.clave] ?? p.defecto, z = r[p.clave] ?? p.defecto
            if distinto(a, z) { d[p.clave] = red(a) }
        }
        return d
    }
}

func nombreValido(_ n: String) -> Bool { n.wholeMatch(of: #/[a-z][a-z0-9-]{0,23}/#) != nil }
