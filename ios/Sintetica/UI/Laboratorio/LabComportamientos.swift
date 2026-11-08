import SwiftUI

/// La duración de un paso: un número o un rango [a, b].
func rangoDura(_ v: Any?) -> (Double, Double) {
    if let l = v as? [NSNumber], l.count == 2 { return (l[0].doubleValue, l[1].doubleValue) }
    let x = (v as? NSNumber)?.doubleValue ?? 1
    return (x, x)
}

func duraDe(_ a: Double, _ b: Double) -> Any {
    let ra = (min(60, max(0.1, a)) * 10).rounded() / 10, rb = (min(60, max(0.1, b)) * 10).rounded() / 10
    return ra == rb ? ra as Any : [min(ra, rb), max(ra, rb)] as Any
}

/// Comportamientos: lo que hace solo, cuando le pasa algo, y sus rutinas. Cada
/// uno es una tira de pasos (una cara un rato). Se prueba en la vista previa.
/// Como web/src/routes/robots/[id]/comportamientos/+page.svelte.
@MainActor
struct LabComportamientos: View {
    let modelo: ModeloRobot
    @State private var tipo = "ocioso"
    @State private var elegido = ""
    @State private var nombre = ""
    @State private var doc: [String: Any] = [:]
    @State private var original = ""
    @State private var paso = 0
    @State private var vista = "pasos"
    @State private var error = ""
    @State private var aviso = ""
    @State private var guardando = false

    private let tipos: [(String, String, String)] = [("ocioso", "Solo", "sun.max"), ("reaccion", "Reacciones", "bolt.fill"), ("rutina", "Rutinas", "moon.fill")]

    private var propios: [String: Any] { modelo.config.comportamientos }
    private func docDe(_ n: String) -> [String: Any]? { propios[n] as? [String: Any] ?? VidaBase.comportamientos[n] }
    private var todos: [String] {
        let base = VidaBase.comportamientos.keys.sorted()
        return base + propios.keys.filter { !base.contains($0) }.sorted()
    }
    private var lista: [String] { todos.filter { (docDe($0)?["tipo"] as? String ?? "ocioso") == tipo } }
    private var pasos: [[String: Any]] { doc["pasos"] as? [[String: Any]] ?? [] }
    private var cambiado: Bool { ConfigDoc(doc).texto != original }
    private var caras: [String] { VidaBase.nombresCaras }
    private var configUsuario: String { modelo.config.paraDibujar }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(tipos, id: \.0) { k, t, i in
                    Button { tipo = k } label: { Label(t, systemImage: i) }.tecla(.negra, chica: true, hundida: tipo == k, ancha: true)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { nuevo() } label: { Label("Nuevo", systemImage: "plus") }.tecla(.negra, chica: true)
                    ForEach(lista, id: \.self) { n in
                        Button { elegir(n) } label: {
                            HStack(spacing: 8) {
                                MiniCara(nombre: primeraCara(n), config: configUsuario, pantalla: modelo.pantalla, ancho: 44)
                                Text(n.replacingOccurrences(of: "-", with: " ")).font(Tipos.marca(11, .bold)).lineLimit(1)
                                if propios[n] != nil { Led(estado: .on, tamano: 6) }
                            }
                            .foregroundStyle(n == elegido ? Color.papel : Color.grisClaro)
                            .padding(6).padding(.trailing, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(n == elegido ? Color.chapa : Color.hundido))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(n == elegido ? Color.brasa : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !doc.isEmpty { mesa }
        }
        .onAppear { if doc.isEmpty { elegir("mirar-alrededor") } }
        .onDisappear { modelo.pausarEspejo(0) }
    }

    private var mesa: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                PantallaNucleo()
                    .aspectRatio(modelo.pantalla.redonda ? 1 : 320 / 172, contentMode: .fit)
                    .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                    .padding(14)
                    .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
                Button { probarAca() } label: { Image(systemName: "play.fill") }.tecla(.naranja, cuadrada: true).padding(10)
                    .accessibilityLabel("Probarlo acá")
            }
            BarraLab(nombre: $nombre, fijo: !elegido.isEmpty && VidaBase.comportamientos[elegido] != nil, enRobot: accionEnRobot, original: accionOriginal,
                     textoOriginal: VidaBase.comportamientos[elegido] != nil ? "Original" : "Borrar", guardar: { Task { await guardar() } },
                     textoGuardar: textoGuardar, puedeGuardar: !guardando && (cambiado || elegido.isEmpty))
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                HStack {
                    Button { vista = "pasos" } label: { Text("Pasos") }.tecla(chica: true, hundida: vista == "pasos")
                    if (doc["tipo"] as? String ?? "ocioso") == "ocioso" {
                        Button { vista = "cuando" } label: { Text("Cuándo") }.tecla(chica: true, hundida: vista == "cuando")
                    }
                    Spacer()
                    Grabado("\(pasos.count) pasos · \(String(format: "%.1f", total)) s", color: Color.tinta.opacity(0.66))
                }
                if vista == "pasos" || (doc["tipo"] as? String ?? "ocioso") != "ocioso" {
                    tira
                    if paso < pasos.count { Bandeja { editorPaso } }
                } else {
                    Bandeja { cuando }
                }
            }
        }
    }

    private var accionEnRobot: (() -> Void)? {
        if elegido.isEmpty || !modelo.conectado { return nil }
        let n = elegido
        return { Task { error = await modelo.probarComportamiento(n) ?? "" } }
    }

    private var accionOriginal: (() -> Void)? {
        if elegido.isEmpty || propios[elegido] == nil { return nil }
        return { Task { await volver() } }
    }

    private var textoGuardar: String {
        if guardando { return "Guardando…" }
        return aviso.isEmpty ? "Guardar" : aviso
    }

    private var total: Double {
        var t = 0.0
        for p in pasos {
            let r = rangoDura(p["dura"])
            t += (r.0 + r.1) / 2
        }
        return t
    }

    private func primeraCara(_ n: String) -> String {
        let l = docDe(n)?["pasos"] as? [[String: Any]] ?? []
        return l.compactMap { $0["cara"] as? String }.first ?? "neutral"
    }

    private var tira: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pasos.indices, id: \.self) { i in
                    let q = pasos[i]
                    let r = rangoDura(q["dura"])
                    Button { paso = i } label: {
                        VStack(spacing: 6) {
                            if let c = q["cara"] as? String {
                                MiniCara(nombre: c, config: configUsuario, pantalla: modelo.pantalla, ancho: 58)
                            } else {
                                Text("·").frame(width: 58, height: 31).foregroundStyle(Color.gris)
                            }
                            Text(r.0 == r.1 ? "\(formato(r.0)) s" : "\(formato(r.0))–\(formato(r.1)) s").font(Tipos.marca(9.5, .heavy))
                                .foregroundStyle(i == paso ? Color.papel : Color.grisClaro)
                        }
                        .padding(6)
                        .frame(minWidth: CGFloat(max(0.6, (r.0 + r.1) / 2)) * 30 + 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(i == paso ? Color.brasa : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                Button { sumarPaso() } label: { Image(systemName: "plus") }.tecla(.negra, cuadrada: true).disabled(pasos.count >= 16)
                    .accessibilityLabel("Sumar un paso")
            }
            .padding(.vertical, 4)
        }
    }

    private func formato(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }

    @ViewBuilder private var editorPaso: some View {
        let p = pasos[paso]
        let r = rangoDura(p["dura"])
        HStack(spacing: 8) {
            Button { moverPaso(-1) } label: { Image(systemName: "arrow.left") }.tecla(.negra, cuadrada: true).disabled(paso == 0)
            Button { moverPaso(1) } label: { Image(systemName: "arrow.right") }.tecla(.negra, cuadrada: true).disabled(paso >= pasos.count - 1)
            Spacer()
            Button { quitarPaso() } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).disabled(pasos.count <= 1)
        }
        VisorMasMenos(rotulo: "Dura", valor: "\(String(format: "%.1f", (r.0 + r.1) / 2)) s", chicos: true,
                      menos: { ponerPaso("dura", duraDe(r.0 - 0.5, r.1 - 0.5)) }, mas: { ponerPaso("dura", duraDe(r.0 + 0.5, r.1 + 0.5)) })
        Grabado("Cara", color: Color.tinta.opacity(0.66))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { ponerPaso("cara", nil) } label: {
                    Text("·").frame(width: 58, height: 31).background(RoundedRectangle(cornerRadius: 8).fill(Color.hundido)).foregroundStyle(Color.gris)
                }
                .buttonStyle(.plain)
                ForEach(caras, id: \.self) { c in
                    Button { ponerPaso("cara", c) } label: {
                        MiniCara(nombre: c, config: configUsuario, pantalla: modelo.pantalla, ancho: 58)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke((p["cara"] as? String) == c ? Color.tinta : Color.clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Grabado("Mira", color: Color.tinta.opacity(0.66))
        Chips(opciones: MIRADAS, elegida: p["mirada"] as? String ?? "libre") { m in ponerPaso("mirada", m == "libre" ? nil : m) }
        Grabado("Le sale", color: Color.tinta.opacity(0.66))
        Chips(opciones: ["—"] + PARTICULAS, elegida: p["particula"] as? String ?? "—", texto: { GLIFO[$0] ?? $0 }) { m in ponerPaso("particula", m == "—" ? nil : m) }
        Grabado("Parpadea", color: Color.tinta.opacity(0.66))
        Chips(opciones: PARPADEOS, elegida: p["parpadeo"] as? String ?? "normal") { m in ponerPaso("parpadeo", m == "normal" ? nil : m) }
    }

    @ViewBuilder private var cuando: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 16) {
            Perilla(nombre: "Ganas", valor: numero("base", 0.3), paso: 0.05, tamano: 54) { v in doc["base"] = v }
            Perilla(nombre: "Seguido", valor: numero("probabilidad", 1), min: 0.01, max: 1, paso: 0.01, tamano: 54) { v in doc["probabilidad"] = v }
            Perilla(nombre: "Espera", valor: numero("enfriamiento", 120), min: 0, max: 3600, paso: 30,
                    mostrar: { $0 < 60 ? "\(Int($0))s" : "\(Int(($0 / 60).rounded()))m" }, tamano: 54) { v in doc["enfriamiento"] = Int(v) }
        }
        Grabado("Le gusta más si es…", color: Color.tinta.opacity(0.66))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 16) {
            ForEach(RASGOS, id: \.self) { r in
                Perilla(nombre: NOMBRES_RASGO[r] ?? r, valor: afinidad(r), min: -1, max: 1, paso: 0.1,
                        mostrar: { $0 > 0 ? "+\(Int(($0 * 10).rounded()))" : "\(Int(($0 * 10).rounded()))" }, tamano: 48) { v in ponerAfinidad(r, v) }
            }
        }
        CampoCondicion(valor: doc["cuando"] as? String ?? "") { t in if t.isEmpty { doc.removeValue(forKey: "cuando") } else { doc["cuando"] = t } }
    }

    private func numero(_ k: String, _ d: Double) -> Double { (doc[k] as? NSNumber)?.doubleValue ?? d }
    private func afinidad(_ r: String) -> Double { ((doc["afinidad"] as? [String: Any])?[r] as? NSNumber)?.doubleValue ?? 0 }

    private func ponerAfinidad(_ r: String, _ v: Double) {
        var a = doc["afinidad"] as? [String: Any] ?? [:]
        if abs(v) < 0.001 { a.removeValue(forKey: r) } else { a[r] = (v * 10).rounded() / 10 }
        if a.isEmpty { doc.removeValue(forKey: "afinidad") } else { doc["afinidad"] = a }
    }

    private func ponerPaso(_ k: String, _ v: Any?) {
        var l = pasos
        guard paso < l.count else { return }
        if let v { l[paso][k] = v } else { l[paso].removeValue(forKey: k) }
        doc["pasos"] = l
    }

    private func moverPaso(_ d: Int) {
        var l = pasos
        let j = paso + d
        guard j >= 0, j < l.count else { return }
        l.swapAt(paso, j)
        doc["pasos"] = l
        paso = j
    }

    private func sumarPaso() {
        var l = pasos
        guard l.count < 16 else { return }
        let c = paso < l.count ? (l[paso]["cara"] as? String ?? "contento") : "contento"
        l.insert(["cara": c, "dura": 1], at: min(l.count, paso + 1))
        doc["pasos"] = l
        paso = min(l.count - 1, paso + 1)
    }

    private func quitarPaso() {
        var l = pasos
        guard l.count > 1, paso < l.count else { return }
        l.remove(at: paso)
        doc["pasos"] = l
        paso = max(0, paso - 1)
    }

    private func elegir(_ n: String) {
        error = ""
        aviso = ""
        elegido = n
        nombre = n
        doc = docDe(n) ?? ["pasos": [["cara": "contento", "dura": 1.5]]]
        original = ConfigDoc(doc).texto
        paso = 0
    }

    private func nuevo() {
        var n = "mi-rutina", k = 2
        while todos.contains(n) { n = "mi-rutina-\(k)"; k += 1 }
        elegido = ""
        nombre = n
        var d: [String: Any] = ["tipo": tipo, "pasos": [["cara": "contento", "dura": 1.5], ["cara": "guino", "dura": 0.8]]]
        if tipo == "ocioso" { d["cuando"] = "aburrimiento>0.3"; d["enfriamiento"] = 120 }
        doc = d
        original = ""
        paso = 0
    }

    private func configCon(_ n: String, _ c: [String: Any]?) -> ConfigDoc {
        var cfg = modelo.config
        cfg.ponerComportamiento(n, c)
        return cfg
    }

    private func probarAca() {
        let c = configCon(nombreValido(nombre) ? nombre : "mi-rutina", doc)
        if let e = Nucleo.validar(c.texto) { error = e; return }
        error = ""
        modelo.pausarEspejo(max(6, total + 2))
        modelo.aplicarEnVistaPrevia(c.texto)
        Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.comportamiento(nombreValido(nombre) ? nombre : "mi-rutina")))
    }

    private func guardar() async {
        error = ""
        guard nombreValido(nombre) else { error = "Minúsculas, sin espacios."; return }
        guardando = true
        let e = await modelo.guardarAhora(configCon(nombre, doc))
        guardando = false
        if let e { error = e; return }
        elegido = nombre
        original = ConfigDoc(doc).texto
        aviso = "Guardado"
        try? await Task.sleep(for: .seconds(2.5))
        aviso = ""
    }

    private func volver() async {
        if let e = await modelo.guardarAhora(configCon(elegido, nil)) { error = e; return }
        elegir(VidaBase.comportamientos[elegido] != nil ? elegido : "mirar-alrededor")
    }
}

/// La condición ("Solo si"), en texto.
struct CampoCondicion: View {
    let valor: String
    let alCambiar: (String) -> Void
    @State private var texto = ""
    var body: some View {
        CampoVisor(rotulo: "Solo si", texto: $texto, ayuda: "aburrimiento>0.3", claro: true, teclado: .asciiCapable) {
            let t = texto.trimmingCharacters(in: .whitespaces)
            if t != valor { alCambiar(t) }
        }
        .onAppear { texto = valor }
        .onChange(of: valor) { _, v in texto = v }
    }
}
