import Foundation

// Los dibujos con formas (las caras v1 del usuario): lo mismo que
// web/src/lib/formato.ts (cajaDe, mover, espejar, CAMPOS y TIPOS_FORMA).
// Coordenadas de la pantalla de referencia: x de −1 a 1 y y de −0,5375
// (arriba) a 0,5375 (abajo).

typealias Forma = [String: Any]

let MEDIO_ALTO = 172.0 / 320

let TIPOS_FORMA: [(tipo: String, nombre: String)] = [
    ("pildora", "Píldora"), ("circulo", "Círculo"), ("corte", "Ojo cortado"), ("arco", "Arco"),
    ("corazon", "Corazón"), ("espiral", "Espiral"), ("poligono", "Polígono"), ("franjas", "Glitch"),
]

let COLORES_FORMA = ["naranja", "naranja-profundo", "tinta", "tinta-suave", "linea", "pantalla"]
let HEX_COLOR_FORMA: [String: UInt32] = [
    "naranja": 0xFF6A33, "naranja-profundo": 0xFF8A5C, "pantalla": 0x0B0A09, "tinta": 0xF5F2EC, "tinta-suave": 0xA39E96, "linea": 0x2C2925,
]

/// Una forma nueva de ese tipo, como la web.
func formaNueva(_ tipo: String) -> Forma {
    switch tipo {
    case "circulo": ["forma": "circulo", "x": 0.0, "y": 0.0, "r": 0.1]
    case "corte": ["forma": "corte", "x": 0.0, "y": 0.0, "w": 0.15, "h": 0.35, "izq": 0.08, "der": 0.0]
    case "arco": ["forma": "arco", "puntos": [[-0.1, 0.05], [0.0, -0.1], [0.1, 0.05]], "trazo": 0.06]
    case "corazon": ["forma": "corazon", "x": 0.0, "y": 0.0, "tamano": 1.0]
    case "espiral": ["forma": "espiral", "x": 0.0, "y": 0.0, "r0": 0.01, "paso": 0.012, "giro": 15.0, "trazo": 0.04]
    case "poligono": ["forma": "poligono", "puntos": [[-0.1, 0.08], [0.0, -0.1], [0.1, 0.08]]]
    case "franjas": ["forma": "franjas", "bandas": [["y": -0.1, "h": 0.05, "dx": 0.04]]]
    default: ["forma": "pildora", "x": 0.0, "y": 0.0, "w": 0.15, "h": 0.4]
    }
}

/// Los campos numéricos de cada forma: clave, etiqueta, mínimo, máximo y paso.
let CAMPOS_FORMA: [String: [(clave: String, nombre: String, min: Double, max: Double, paso: Double)]] = [
    "pildora": [("x", "x", -2, 2, 0.005), ("y", "y", -2, 2, 0.005), ("w", "ancho", 0, 2, 0.005), ("h", "alto", 0, 2, 0.005),
                ("r", "radio", 0, 2, 0.005), ("trazo", "trazo", 0, 2, 0.005)],
    "corte": [("x", "x", -2, 2, 0.005), ("y", "y", -2, 2, 0.005), ("w", "ancho", 0, 2, 0.005), ("h", "alto", 0, 2, 0.005),
              ("izq", "corte izq.", 0, 2, 0.005), ("der", "corte der.", 0, 2, 0.005)],
    "circulo": [("x", "x", -2, 2, 0.005), ("y", "y", -2, 2, 0.005), ("r", "radio", 0, 2, 0.005)],
    "arco": [("trazo", "trazo", 0, 2, 0.005)],
    "corazon": [("x", "x", -2, 2, 0.005), ("y", "y", -2, 2, 0.005), ("tamano", "tamaño", 0, 2, 0.01)],
    "espiral": [("x", "x", -2, 2, 0.005), ("y", "y", -2, 2, 0.005), ("r0", "radio inicial", 0, 2, 0.002), ("paso", "paso", 0, 2, 0.001),
                ("giro", "vueltas (rad)", 0, 40, 0.1), ("trazo", "trazo", 0, 2, 0.005)],
    "poligono": [],
    "franjas": [],
]

private func num(_ f: Forma, _ k: String) -> Double? { (f[k] as? NSNumber)?.doubleValue }
private func red(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }

private func puntos(_ f: Forma) -> [[Double]]? {
    (f["puntos"] as? [Any])?.map { p in ((p as? [Any]) ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 } }
}

/// Las campos visibles de una forma (sin el radio de una píldora que no tiene uno propio ni el trazo si está rellena).
func camposVisibles(_ f: Forma) -> [(clave: String, nombre: String, min: Double, max: Double, paso: Double)] {
    let tipo = f["forma"] as? String ?? ""
    return (CAMPOS_FORMA[tipo] ?? []).filter { c in
        if tipo == "pildora", c.clave == "r", f["r"] == nil { return false }
        if tipo == "pildora", c.clave == "trazo", (f["relleno"] as? Bool) != false { return false }
        return true
    }
}

/// La caja de una forma (x0, y0, x1, y1), como cajaDeForma del núcleo.
func cajaDe(_ f: Forma) -> (Double, Double, Double, Double) {
    let x = num(f, "x") ?? 0, y = num(f, "y") ?? 0
    switch f["forma"] as? String ?? "" {
    case "pildora", "corte":
        let w = num(f, "w") ?? 0, h = num(f, "h") ?? 0
        return (x - w / 2, y - h / 2, x + w / 2, y + h / 2)
    case "circulo":
        let r = num(f, "r") ?? 0
        return (x - r, y - r, x + r, y + r)
    case "corazon":
        let k = (num(f, "tamano") ?? 1) / 160
        return (x - 24 * k, y - 18 * k, x + 24 * k, y + 21.4 * k)
    case "espiral":
        let r = (num(f, "r0") ?? 0) + (num(f, "paso") ?? 0) * (num(f, "giro") ?? 0)
        return (x - r, y - r, x + r, y + r)
    case "arco", "poligono":
        let p = puntos(f) ?? [[0, 0]]
        let xs = p.map { $0.first ?? 0 }, ys = p.map { $0.count > 1 ? $0[1] : 0 }
        return (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
    case "franjas":
        let b = f["bandas"] as? [[String: Any]] ?? []
        if b.isEmpty { return (-1, 0, 1, 0) }
        let y0 = b.map { ($0["y"] as? NSNumber)?.doubleValue ?? 0 }.min() ?? 0
        let y1 = b.map { (($0["y"] as? NSNumber)?.doubleValue ?? 0) + (($0["h"] as? NSNumber)?.doubleValue ?? 0) }.max() ?? 0
        return (-1, y0, 1, y1)
    default:
        return (x, y, x, y)
    }
}

/// La forma corrida dx, dy.
func moverForma(_ f: Forma, _ dx: Double, _ dy: Double) -> Forma {
    var g = f
    if let p = puntos(f) { g["puntos"] = p.map { [red(($0.first ?? 0) + dx), red(($0.count > 1 ? $0[1] : 0) + dy)] } }
    if let b = f["bandas"] as? [[String: Any]] {
        g["bandas"] = b.map { x -> [String: Any] in
            var y = x
            y["y"] = red(((x["y"] as? NSNumber)?.doubleValue ?? 0) + dy)
            return y
        }
    }
    if let x = num(f, "x") { g["x"] = red(x + dx) }
    if let y = num(f, "y") { g["y"] = red(y + dy) }
    return g
}

/// El mismo ojo del otro lado (x → −x).
func espejarForma(_ f: Forma) -> Forma {
    var g = f
    if let x = num(f, "x") { g["x"] = red(-x) }
    if let p = puntos(f) { g["puntos"] = Array(p.map { [red(-($0.first ?? 0)), $0.count > 1 ? $0[1] : 0] }.reversed()) }
    if f["forma"] as? String == "corte" {
        g["izq"] = f["der"]
        g["der"] = f["izq"]
    }
    return g
}

/// La primera forma (desde arriba) que tiene ese punto adentro (con un margen para tocarla con el dedo).
func formaEn(_ formas: [Forma], x: Double, y: Double, margen: Double = 0.04) -> Int? {
    for i in formas.indices.reversed() {
        let c = cajaDe(formas[i])
        if x >= c.0 - margen, x <= c.2 + margen, y >= c.1 - margen, y <= c.3 + margen { return i }
    }
    return nil
}

/// Un punto de la vista (0 a 1) a coordenadas de la pantalla de referencia.
func aNormal(_ fx: Double, _ fy: Double) -> (Double, Double) { (fx * 2 - 1, fy * 2 * MEDIO_ALTO - MEDIO_ALTO) }
