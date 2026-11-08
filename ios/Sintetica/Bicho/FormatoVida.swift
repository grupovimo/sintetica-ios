import Foundation

// El paquete de vida de la config v2 (web/src/lib/formato.ts): habla,
// despertador, ubicación, cuidado y avisos del celu.

let MAX_FRASES = 12
let MAX_TEXTO = 60
let MAX_AVISOS = 8
let MAX_DECIR_AVISO = 40
let MAX_NOMBRE_AVISO = 24

/// Las situaciones en las que habla solo.
let SITUACIONES = [
    "despertar", "buenas-noches", "volviste", "te-extrane", "aburrido", "sueno", "bateria-baja", "cargando", "caricia", "saludo", "hito",
    "cumple-dueno", "cumple-robot", "recordatorio-hecho", "despertador", "posponer", "clima-frio", "clima-calor", "clima-lluvia", "clima-lindo",
]
let NOMBRES_SITUACION: [String: String] = [
    "despertar": "Al despertar", "buenas-noches": "Buenas noches", "volviste": "Volviste", "te-extrane": "Te extrañó", "aburrido": "Aburrido",
    "sueno": "Con sueño", "bateria-baja": "Sin pila", "cargando": "Cargando", "caricia": "Caricia", "saludo": "Saludo", "hito": "Un hito",
    "cumple-dueno": "Tu cumple", "cumple-robot": "Su cumple", "recordatorio-hecho": "Recordatorio hecho", "despertador": "Despertador",
    "posponer": "Posponer", "clima-frio": "Hace frío", "clima-calor": "Hace calor", "clima-lluvia": "Llueve", "clima-lindo": "Día lindo",
]
let NOMBRES_JUEGO: [String: String] = ["ppt": "Piedra papel tijera", "reflejos": "Reflejos", "mirada": "Mirada", "dado": "Dado", "moneda": "Moneda"]

/// Un solo despertador por robot: suena creciente y se pospone.
struct Despertador: Equatable {
    var hora = "07:30"
    var dias = ""          // vacío = todos
    var activo = true
    var sonido = true
    var texto = ""
    var posponer = 9

    /// Sin config se ve apagado; tocar algo lo prende con estos valores.
    static let porDefecto = Despertador(hora: "07:30", dias: "LMXJV", activo: true, sonido: true, texto: "", posponer: 9)

    init(hora: String = "07:30", dias: String = "", activo: Bool = true, sonido: Bool = true, texto: String = "", posponer: Int = 9) {
        self.hora = hora; self.dias = dias; self.activo = activo; self.sonido = sonido; self.texto = texto; self.posponer = posponer
    }

    init(_ o: [String: Any]) {
        hora = o["hora"] as? String ?? "07:30"
        dias = o["dias"] as? String ?? ""
        activo = o["activo"] as? Bool ?? true
        sonido = o["sonido"] as? Bool ?? true
        texto = o["texto"] as? String ?? ""
        posponer = (o["posponer"] as? NSNumber)?.intValue ?? 9
    }

    var objeto: [String: Any] {
        var o: [String: Any] = ["hora": hora, "activo": activo, "sonido": sonido, "posponer": posponer]
        if !dias.isEmpty, dias.count < 7 { o["dias"] = dias }
        if !texto.isEmpty { o["texto"] = texto }
        return o
    }

    var todosLosDias: String { dias.isEmpty ? "LMXJVSD" : dias }

    /// Prende o apaga un día (nunca deja ninguno).
    mutating func alternar(_ l: String) {
        let ya = todosLosDias
        let nuevo = DIAS_SEMANA.map(\.letra).filter { $0 == l ? !ya.contains($0) : ya.contains($0) }.joined()
        if !nuevo.isEmpty { dias = nuevo.count == 7 ? "" : nuevo }
    }
}

/// Cuidarte: agua, pausa activa, "¿cómo estás?", y por Telegram que te extrañe y te cuente su día.
struct Cuidado: Equatable {
    var agua = 0            // horas (0 = nunca; 1 a 8)
    var pausa = 0           // minutos sin tocarlo (0 = nunca; 30 a 240)
    var desde = "09:00", hasta = "18:00", diasTrabajo = "LMXJV"
    var animo = true
    var extranar = true
    var extranarDias = 2    // 1 a 7
    var resumen = false

    init() {}

    init(_ o: [String: Any]) {
        agua = (o["agua"] as? NSNumber)?.intValue ?? 0
        pausa = (o["pausa"] as? NSNumber)?.intValue ?? 0
        let t = o["trabajo"] as? [String: Any] ?? [:]
        desde = t["desde"] as? String ?? "09:00"
        hasta = t["hasta"] as? String ?? "18:00"
        diasTrabajo = t["dias"] as? String ?? "LMXJV"
        animo = o["animo"] as? Bool ?? true
        extranar = o["extranar"] as? Bool ?? true
        extranarDias = (o["extranarDias"] as? NSNumber)?.intValue ?? 2
        resumen = o["resumen"] as? Bool ?? false
    }

    var objeto: [String: Any] {
        ["agua": agua, "pausa": pausa, "trabajo": ["desde": desde, "hasta": hasta, "dias": diasTrabajo],
         "animo": animo, "extranar": extranar, "extranarDias": extranarDias, "resumen": resumen]
    }

    /// La pausa salta de "no" a 30 minutos (menos no tiene sentido).
    mutating func ponerPausa(_ v: Int) { pausa = v <= 0 ? 0 : max(30, min(240, v)) }

    mutating func moverTrabajo(desde esDesde: Bool, _ d: Int) {
        let nuevo = sumarMinutos(esDesde ? desde : hasta, d)
        if nuevo == (esDesde ? hasta : desde) { return }
        if esDesde { desde = nuevo } else { hasta = nuevo }
    }

    mutating func alternarDia(_ l: String) {
        let nuevo = DIAS_SEMANA.map(\.letra).filter { $0 == l ? !diasTrabajo.contains($0) : diasTrabajo.contains($0) }.joined()
        if !nuevo.isEmpty { diasTrabajo = nuevo }
    }
}

/// Cómo reacciona a un aviso del celu (el primero que coincide gana).
struct AvisoCelu: Equatable {
    var tipo = "notificacion"  // o "llamada"
    var app = "", contacto = "", expresion = "", comportamiento = "", decir = ""
    var sonido = true

    init(tipo: String = "notificacion", expresion: String = "", decir: String = "") {
        self.tipo = tipo; self.expresion = expresion; self.decir = decir
    }

    init(_ o: [String: Any]) {
        tipo = o["tipo"] as? String ?? "notificacion"
        app = o["app"] as? String ?? ""
        contacto = o["contacto"] as? String ?? ""
        expresion = o["expresion"] as? String ?? ""
        comportamiento = o["comportamiento"] as? String ?? ""
        decir = o["decir"] as? String ?? ""
        sonido = o["sonido"] as? Bool ?? true
    }

    /// Sin los vacíos y sin "sonido" si suena (como la web).
    var objeto: [String: Any] {
        var o: [String: Any] = ["tipo": tipo]
        if !app.isEmpty { o["app"] = cortarBytes(app, MAX_NOMBRE_AVISO) }
        if !contacto.isEmpty { o["contacto"] = cortarBytes(contacto, MAX_NOMBRE_AVISO) }
        if !expresion.isEmpty { o["expresion"] = expresion }
        if !comportamiento.isEmpty { o["comportamiento"] = comportamiento }
        if !decir.isEmpty { o["decir"] = cortarBytes(decir, MAX_DECIR_AVISO) }
        if !sonido { o["sonido"] = false }
        return o
    }
}

/// Dónde vive, para el clima.
struct Ubicacion: Equatable {
    var lat: Double, lon: Double, ciudad: String
}

extension ConfigDoc {
    // --- Habla ---
    var frecuenciaHabla: Double { ((raiz["habla"] as? [String: Any])?["frecuencia"] as? NSNumber)?.doubleValue ?? 0.5 }
    var frasesPropias: [String: [String]] { ((raiz["habla"] as? [String: Any])?["propias"] as? [String: [String]]) ?? [:] }
    var totalFrases: Int { frasesPropias.values.reduce(0) { $0 + $1.count } }

    mutating func ponerFrecuenciaHabla(_ v: Double) {
        var h = raiz["habla"] as? [String: Any] ?? [:]
        h["frecuencia"] = v
        raiz["habla"] = h
    }

    mutating func ponerFrases(_ situacion: String, _ l: [String]) {
        var h = raiz["habla"] as? [String: Any] ?? [:]
        var p = frasesPropias
        if l.isEmpty { p.removeValue(forKey: situacion) } else { p[situacion] = l }
        if p.isEmpty { h.removeValue(forKey: "propias") } else { h["propias"] = p }
        if h.isEmpty { raiz.removeValue(forKey: "habla") } else { raiz["habla"] = h }
    }

    // --- Despertador ---
    var despertador: Despertador? { (raiz["despertador"] as? [String: Any]).map { Despertador($0) } }
    /// El que se ve: sin config, el de siempre apagado.
    var despertadorVisible: Despertador {
        if let d = despertador { return d }
        var d = Despertador.porDefecto
        d.activo = false
        return d
    }

    mutating func cambiarDespertador(_ f: (inout Despertador) -> Void) {
        var d = despertador ?? Despertador.porDefecto
        f(&d)
        raiz["despertador"] = d.objeto
    }

    // --- Ubicación ---
    var ubicacion: Ubicacion? {
        guard let u = raiz["ubicacion"] as? [String: Any], let lat = (u["lat"] as? NSNumber)?.doubleValue,
              let lon = (u["lon"] as? NSNumber)?.doubleValue else { return nil }
        return Ubicacion(lat: lat, lon: lon, ciudad: u["ciudad"] as? String ?? "")
    }

    mutating func ponerUbicacion(_ u: Ubicacion) {
        let r = { (x: Double) in (x * 10000).rounded() / 10000 }
        var o: [String: Any] = ["lat": r(u.lat), "lon": r(u.lon)]
        let c = cortarBytes(u.ciudad, 40)
        if !c.isEmpty { o["ciudad"] = c }
        raiz["ubicacion"] = o
    }

    // --- Cuidado ---
    var cuidado: Cuidado { (raiz["cuidado"] as? [String: Any]).map { Cuidado($0) } ?? Cuidado() }
    mutating func cambiarCuidado(_ f: (inout Cuidado) -> Void) {
        var c = cuidado
        f(&c)
        raiz["cuidado"] = c.objeto
    }

    // --- Avisos del celu ---
    var avisos: [AvisoCelu] {
        get { (raiz["avisos"] as? [[String: Any]] ?? []).map { AvisoCelu($0) } }
        set {
            let l = Array(newValue.prefix(MAX_AVISOS))
            if l.isEmpty { raiz.removeValue(forKey: "avisos") } else { raiz["avisos"] = l.map(\.objeto) }
        }
    }
}

/// Las frases con {dueno} y {robot} ya puestos (para probarlas).
func armarFrase(_ f: String, dueno: String, robot: String) -> String {
    let t = f.replacingOccurrences(of: "{dueno}", with: dueno).replacingOccurrences(of: "{robot}", with: robot)
    let limpio = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return cortarBytes(limpio, MAX_TEXTO)
}
