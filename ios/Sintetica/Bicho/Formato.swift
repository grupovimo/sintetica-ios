import Foundation

// El formato de la config (shared/formato/config.schema.json) para la consola.
// Igual que web/src/lib/formato.ts y web/src/lib/consola/guardado.svelte.ts.

/// El robot cuenta los textos en bytes UTF-8 (una tilde ocupa 2): se corta sin partir una letra.
/// Como el núcleo, por code point (no por Character: "👍🏽" son dos y entra el 👍 solo).
func cortarBytes(_ t: String, _ max: Int) -> String {
    var r = String.UnicodeScalarView()
    var n = 0
    for u in t.unicodeScalars {
        let b = UTF8.width(u)
        if n + b > max { break }
        r.append(u)
        n += b
    }
    return String(r)
}

let RASGOS = ["energia", "sociabilidad", "picardia", "timidez", "curiosidad", "malGenio"]
let NOMBRES_RASGO: [String: String] = [
    "energia": "Energía", "sociabilidad": "Sociabilidad", "picardia": "Picardía",
    "timidez": "Timidez", "curiosidad": "Curiosidad", "malGenio": "Mal genio",
]
let NOMBRES_PRESET: [String: String] = [
    "equilibrado": "Equilibrado", "timido": "Tímido", "picaro": "Pícaro", "dormilon": "Dormilón", "carinoso": "Cariñoso",
    "curioso": "Curioso", "grunon": "Gruñón", "electrico": "Eléctrico",
]
let DICE_PRESET: [String: String] = [
    "picaro": "Bromas, guiños y atención.",
    "timido": "Se esconde y de a poco se suelta.",
    "carinoso": "Te busca y te extraña.",
    "curioso": "Investiga cada ruido.",
    "dormilon": "Siestas largas.",
    "grunon": "Rezonga, pero te quiere.",
    "electrico": "No para nunca.",
    "equilibrado": "Un poco de todo.",
]
/// Los rasgos de cada preset (shared/formato/vida/personalidades.json).
func rasgosDePreset(_ p: String) -> [String: Double] {
    guard let r = EditorConfig.presets.first(where: { $0.clave == p })?.rasgos else { return [:] }
    return Dictionary(uniqueKeysWithValues: zip(RASGOS, r))
}

let NOMBRES_EVENTO: [String: String] = [
    "tacto": "Lo tocan", "doble-toque": "Doble toque", "levantado": "Lo levantan", "sacudida": "Lo sacuden",
    "boca-abajo": "Boca abajo", "vinculado": "Se vincula", "app-abierta": "Abren la app", "despertado": "Lo despiertan",
    "caricia": "Una caricia", "muchos-toques": "Muchos toques", "sacudida-suave": "Sacudida suave",
    "sacudida-fuerte": "Sacudida fuerte", "inclinado": "Lo inclinan", "caida": "Se cae", "voz": "Le hablan", "nombre": "Su nombre",
    "ruido": "Un ruido", "musica": "Música", "silencio": "Silencio", "notificacion": "Notificación",
    "llamada": "Una llamada", "bateria-baja": "Batería baja", "bateria-critica": "Batería crítica",
    "enchufado": "Lo enchufan", "desenchufado": "Lo desenchufan", "cargado": "Carga completa", "sin-wifi": "Sin WiFi",
    "cambio-de-cara": "Cambio de cara", "bicho-cerca": "Otro robot cerca", "volvio": "Volvés",
    "hito": "Un hito", "recordatorio": "Recordatorio", "pomodoro": "Fin de tanda",
    "despertador": "Despertador", "juego": "Un juego", "animo": "Su ánimo",
    "cara-detectada": "Te ve", "oscuridad": "Se apaga la luz", "mano-cerca": "Una mano cerca",
    "toque-recibido": "Le llega un toque", "devolver-toque": "Devolvés un toque", "agenda": "Se viene un evento",
    "llegaste": "Llegás", "te-fuiste": "Te vas", "habito": "Marcás un hábito",
]

let MAX_RECORDATORIOS = 12
let MAX_TEXTO_RECORDATORIO = 40
let MAX_REGLAS = 24
let MAX_LISTA = 16
let MAX_PALABRA = 16
/// Nombres (del robot, del dueño, de expresiones y comportamientos), en bytes.
let MAX_NOMBRE = 24
let DIAS_SEMANA: [(letra: String, nombre: String)] = [
    ("L", "Lunes"), ("M", "Martes"), ("X", "Miércoles"), ("J", "Jueves"), ("V", "Viernes"), ("S", "Sábado"), ("D", "Domingo"),
]

/// Un recordatorio: a la hora, el robot lo muestra en su pantalla hasta que lo tocan.
/// dias: letras de L M X J V S D (vacío = todos los días).
struct Recordatorio: Equatable {
    var hora: String
    var dias: String = ""
    var texto: String
    var expresion: String? = nil
    var sonido: Bool? = nil
    var activo: Bool? = nil

    init(hora: String, dias: String = "", texto: String, expresion: String? = nil, sonido: Bool? = nil, activo: Bool? = nil) {
        self.hora = hora; self.dias = dias; self.texto = texto; self.expresion = expresion; self.sonido = sonido; self.activo = activo
    }

    init?(_ o: [String: Any]) {
        guard let h = o["hora"] as? String, let t = o["texto"] as? String else { return nil }
        hora = h
        texto = t
        dias = o["dias"] as? String ?? ""
        expresion = o["expresion"] as? String
        sonido = o["sonido"] as? Bool
        activo = o["activo"] as? Bool
    }

    var objeto: [String: Any] {
        var o: [String: Any] = ["hora": hora, "texto": texto]
        if !dias.isEmpty { o["dias"] = dias }
        if let expresion { o["expresion"] = expresion }
        if let sonido { o["sonido"] = sonido }
        if let activo { o["activo"] = activo }
        return o
    }

    var prendido: Bool { activo != false }
    func tiene(_ letra: String) -> Bool { dias.isEmpty || dias.contains(letra) }

    /// Prende o apaga un día (vacío = todos: se arranca de todos), como la web.
    mutating func alternar(_ letra: String) {
        var d = Set(dias.map(String.init))
        if d.isEmpty { for x in DIAS_SEMANA { d.insert(x.letra) } }
        if d.contains(letra) { d.remove(letra) } else { d.insert(letra) }
        let orden = DIAS_SEMANA.map(\.letra).filter { d.contains($0) }.joined()
        dias = orden.count == 7 ? "" : orden
    }

    /// Uno nuevo: a la hora en punto que viene.
    static func nuevo(ahora: Date = Date(), calendario: Calendar = .current) -> Recordatorio {
        let h = calendario.component(.hour, from: ahora.addingTimeInterval(3600))
        return Recordatorio(hora: String(format: "%02d:00", h), texto: "Tomar agua")
    }
}

/// Una regla: cuando pasa `si` (y se cumple `y`), hace `entonces`.
struct Regla: Equatable {
    var si: String
    var y: String? = nil
    var entonces: [String]

    init(si: String, y: String? = nil, entonces: [String]) { self.si = si; self.y = y; self.entonces = entonces }

    init?(_ o: [String: Any]) {
        guard let s = o["si"] as? String, let e = o["entonces"] as? [String] else { return nil }
        si = s
        y = o["y"] as? String
        entonces = e
    }

    var objeto: [String: Any] {
        var o: [String: Any] = ["si": si, "entonces": entonces]
        if let y, !y.isEmpty { o["y"] = y }
        return o
    }
}

/// La config como JSON (sin perder lo que la consola no edita).
struct ConfigDoc {
    var raiz: [String: Any]

    init(_ raiz: [String: Any] = ["version": 2]) { self.raiz = raiz }

    init(texto: String) {
        raiz = (try? JSONSerialization.jsonObject(with: Data(texto.utf8))) as? [String: Any] ?? ["version": 1]
    }

    var texto: String {
        let d = (try? JSONSerialization.data(withJSONObject: raiz, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"version\":2}".utf8)
        return String(decoding: d, as: UTF8.self)
    }

    /// La consola siempre escribe la v2: la v1 decía cuándo duerme ("sueno": "HH:MM-HH:MM").
    mutating func aV2() {
        if var p = raiz["personalidad"] as? [String: Any], let s = p["sueno"] as? String, s.count == 11 {
            if raiz["horario"] == nil {
                raiz["horario"] = ["despierta": String(s.suffix(5)), "duerme": String(s.prefix(5))]
            }
            p.removeValue(forKey: "sueno")
            raiz["personalidad"] = p
        }
        raiz["version"] = 2
    }

    private func objeto(_ k: String) -> [String: Any] { raiz[k] as? [String: Any] ?? [:] }
    private mutating func poner(_ k: String, _ o: [String: Any]?) {
        if let o, !o.isEmpty { raiz[k] = o } else { raiz.removeValue(forKey: k) }
    }

    // --- Nombre y carácter ---
    var nombre: String? {
        get { raiz["nombre"] as? String }
        set { if let n = newValue, !n.isEmpty { raiz["nombre"] = n } else { raiz.removeValue(forKey: "nombre") } }
    }

    var preset: String { objeto("personalidad")["preset"] as? String ?? "equilibrado" }
    var tienePreset: Bool { objeto("personalidad")["preset"] != nil }

    func rasgo(_ r: String) -> Double {
        (objeto("personalidad")[r] as? NSNumber)?.doubleValue ?? rasgosDePreset(preset)[r] ?? 0.5
    }

    mutating func ponerPreset(_ p: String) {
        var o: [String: Any] = ["preset": p]
        for (k, v) in rasgosDePreset(p) { o[k] = v }
        raiz["personalidad"] = o
    }

    mutating func ponerRasgo(_ r: String, _ v: Double) {
        var o = objeto("personalidad")
        o[r] = v
        raiz["personalidad"] = o
    }

    // --- Cara ---
    var colorOjos: String { ((objeto("cara")["color"] as? String) ?? "#FF6A33").uppercased() }
    var tamano: Double { (objeto("cara")["tamano"] as? NSNumber)?.doubleValue ?? 1 }

    mutating func ponerColor(_ hex: String) {
        var c = objeto("cara")
        if hex.uppercased() == "#FF6A33" { c.removeValue(forKey: "color") } else { c["color"] = hex }
        poner("cara", c)
    }

    mutating func ponerTamano(_ v: Double) {
        var c = objeto("cara")
        c["tamano"] = v
        poner("cara", c)
    }

    var brilloMax: Double { (objeto("limites_marca")["brillo_max"] as? NSNumber)?.doubleValue ?? 0.9 }
    mutating func ponerBrillo(_ v: Double) {
        var l = objeto("limites_marca")
        l["brillo_max"] = v
        poner("limites_marca", l)
    }

    // --- Su día ---
    var despierta: String { objeto("horario")["despierta"] as? String ?? "08:00" }
    var duerme: String { objeto("horario")["duerme"] as? String ?? "23:30" }

    /// Mueve una de las dos horas (no deja que queden iguales).
    mutating func moverHorario(despierta cual: Bool, minutos d: Int) {
        let a = despierta, z = duerme
        let nuevo = sumarMinutos(cual ? a : z, d)
        if nuevo == (cual ? z : a) { return }
        raiz["horario"] = ["despierta": cual ? nuevo : a, "duerme": cual ? z : nuevo]
    }

    mutating func ponerHorario(despierta: String, duerme: String) { raiz["horario"] = ["despierta": despierta, "duerme": duerme] }

    var nombreDueno: String { objeto("dueno")["nombre"] as? String ?? "" }
    var cumpleDueno: String? { objeto("dueno")["cumple"] as? String }
    var cumpleRobot: String? { raiz["cumple"] as? String }

    mutating func ponerNombreDueno(_ n: String) {
        var d = objeto("dueno")
        let v = cortarBytes(n.trimmingCharacters(in: .whitespaces), MAX_NOMBRE)
        if v.isEmpty { d.removeValue(forKey: "nombre") } else { d["nombre"] = v }
        poner("dueno", d)
    }

    /// m y d en 0 = sin cumple.
    mutating func ponerCumple(robot: Bool, mes m: Int, dia d: Int) {
        let v: String? = m > 0 && d > 0 ? String(format: "%02d-%02d", m, Swift.min(d, DIAS_POR_MES[m - 1])) : nil
        if robot {
            if let v { raiz["cumple"] = v } else { raiz.removeValue(forKey: "cumple") }
        } else {
            var o = objeto("dueno")
            if let v { o["cumple"] = v } else { o.removeValue(forKey: "cumple") }
            poner("dueno", o)
        }
    }

    // --- Lista, imágenes y protector ---
    var lista: [String] { raiz["lista"] as? [String] ?? [] }
    func enLista(_ espacio: Int) -> Bool { lista.contains("imagen:\(espacio)") }

    /// Sumarla a lo que muestra: si la lista estaba vacía, primero va su cara.
    mutating func mostrar(_ espacio: Int, _ si: Bool) {
        var l = lista.isEmpty ? ["cara:neutral"] : lista
        let k = "imagen:\(espacio)"
        if si { if !l.contains(k) { l = Array((l + [k]).prefix(MAX_LISTA)) } } else { l.removeAll { $0 == k } }
        if l.isEmpty || l == ["cara:neutral"] { raiz.removeValue(forKey: "lista") } else { raiz["lista"] = l }
    }

    var protector: Int? { (objeto("protector")["imagen"] as? NSNumber)?.intValue }
    var esperaProtector: Int { (objeto("protector")["espera"] as? NSNumber)?.intValue ?? 10 }

    mutating func ponerProtector(_ espacio: Int?) {
        guard let espacio else { raiz.removeValue(forKey: "protector"); return }
        var p: [String: Any] = ["imagen": espacio]
        if let e = (objeto("protector")["espera"] as? NSNumber)?.intValue { p["espera"] = e }
        raiz["protector"] = p
    }

    static let ESPERAS = [3, 5, 10, 30, 60, 300, 900, 3600]
    mutating func moverEspera(_ d: Int) {
        guard var p = raiz["protector"] as? [String: Any] else { return }
        let i = Swift.max(0, ConfigDoc.ESPERAS.firstIndex { $0 >= esperaProtector } ?? 0)
        p["espera"] = ConfigDoc.ESPERAS[Swift.min(ConfigDoc.ESPERAS.count - 1, Swift.max(0, i + d))]
        raiz["protector"] = p
    }

    // --- Recordatorios ---
    var recordatorios: [Recordatorio] {
        get { (raiz["recordatorios"] as? [[String: Any]] ?? []).compactMap { Recordatorio($0) } }
        set {
            let l = Array(newValue.prefix(MAX_RECORDATORIOS))
            if l.isEmpty { raiz.removeValue(forKey: "recordatorios") } else { raiz["recordatorios"] = l.map(\.objeto) }
        }
    }

    // --- Modos ---
    var modo: String { raiz["modo"] as? String ?? "mascota" }
    mutating func ponerModo(_ m: String) { if m == "mascota" { raiz.removeValue(forKey: "modo") } else { raiz["modo"] = m } }
    var trabajo: Int { (objeto("pomodoro")["trabajo"] as? NSNumber)?.intValue ?? 25 }
    var descanso: Int { (objeto("pomodoro")["descanso"] as? NSNumber)?.intValue ?? 5 }
    mutating func moverPomodoro(trabajo esTrabajo: Bool, _ d: Int) {
        var t = trabajo, s = descanso
        if esTrabajo { t = Swift.min(120, Swift.max(1, t + d)) } else { s = Swift.min(60, Swift.max(1, s + d)) }
        raiz["pomodoro"] = ["trabajo": t, "descanso": s]
    }

    // --- Reglas ---
    var reglas: [Regla] {
        get { (raiz["reglas"] as? [[String: Any]] ?? []).compactMap { Regla($0) } }
        set {
            let l = Array(newValue.prefix(MAX_REGLAS))
            if l.isEmpty { raiz.removeValue(forKey: "reglas") } else { raiz["reglas"] = l.map(\.objeto) }
        }
    }

    // --- Voz ---
    var voz: [String: Any] { objeto("voz") }
    mutating func ponerVoz(_ k: String, _ v: Any?) {
        var o = voz
        if let v { o[k] = v } else { o.removeValue(forKey: k) }
        poner("voz", o)
    }

    // --- Expresiones y comportamientos propios ---
    var expresiones: [String: Any] { objeto("expresiones") }
    mutating func ponerExpresion(_ n: String, _ doc: [String: Any]?) {
        var e = expresiones
        if let doc { e[n] = doc } else { e.removeValue(forKey: n) }
        poner("expresiones", e)
    }

    var comportamientos: [String: Any] { objeto("comportamientos") }
    mutating func ponerComportamiento(_ n: String, _ doc: [String: Any]?) {
        var c = comportamientos
        if let doc { c[n] = doc } else { c.removeValue(forKey: n) }
        poner("comportamientos", c)
    }

    var animaciones: [String] { objeto("animaciones").keys.sorted() }

    /// Lo justo para dibujar las caras paramétricas: el color y las propias
    /// (sin dibujos de formas), para el núcleo sin tocar la instancia.
    var paraDibujar: String {
        var o: [String: Any] = ["version": 2]
        if let c = raiz["cara"] as? [String: Any], let color = c["color"] { o["cara"] = ["color": color] }
        let propias = expresiones.filter { ($0.value as? [String: Any])?["formas"] == nil }
        if !propias.isEmpty { o["expresiones"] = propias }
        return ConfigDoc(o).texto
    }
}

let DIAS_POR_MES = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
let MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

func aMinutos(_ h: String) -> Int {
    let p = h.split(separator: ":")
    guard p.count == 2, let a = Int(p[0]), let b = Int(p[1]) else { return 0 }
    return a * 60 + b
}

func sumarMinutos(_ h: String, _ d: Int) -> String {
    let x = ((aMinutos(h) + d) % 1440 + 1440) % 1440
    return String(format: "%02d:%02d", x / 60, x % 60)
}

/// "MM-DD" en (mes, día); (0, 0) si no hay.
func partesCumple(_ s: String?) -> (mes: Int, dia: Int) {
    guard let s, s.count == 5 else { return (0, 0) }
    return (Int(s.prefix(2)) ?? 0, Int(s.suffix(2)) ?? 0)
}
