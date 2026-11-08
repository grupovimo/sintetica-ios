import SwiftUI

let ESTADO_VIDA = ["energia", "animo", "afecto", "aburrimiento", "curiosidad", "sueno", "estres"]
let NOMBRES_ESTADO: [String: String] = [
    "energia": "Energía", "animo": "Ánimo", "afecto": "Afecto", "aburrimiento": "Aburrimiento", "curiosidad": "Curiosidad", "sueno": "Sueño", "estres": "Estrés",
]

/// El ícono de cada grupo de eventos.
func iconoEvento(_ e: String) -> String {
    switch e {
    case "tacto", "doble-toque", "caricia", "muchos-toques", "despertado": "hand.tap.fill"
    case "levantado", "sacudida", "sacudida-suave", "sacudida-fuerte", "boca-abajo", "inclinado", "caida": "move.3d"
    case "voz", "nombre", "ruido", "musica", "silencio": "waveform"
    case "volvio", "hito", "bicho-cerca", "cambio-de-cara", "vinculado", "app-abierta": "heart.fill"
    default: "battery.75percent"
    }
}

/// Una acción de regla partida: "reflejo:contento" → (reflejo, contento); "estado.animo+0.2" → (estado, animo+0.2).
func partirAccion(_ a: String) -> (String, String) {
    if a.hasPrefix("estado.") { return ("estado", String(a.dropFirst(7))) }
    guard let i = a.firstIndex(of: ":") else { return (a, "") }
    return (String(a[..<i]), String(a[a.index(after: i)...]))
}

func unirAccion(_ tipo: String, _ arg: String) -> String { tipo == "estado" ? "estado.\(arg)" : "\(tipo):\(arg)" }

/// Reglas: cuando le pasa algo, qué hace. Se elige el evento en la botonera,
/// se ve qué responde (las tuyas y las de fábrica) y se prueba en la vista
/// previa. Como web/src/routes/robots/[id]/reglas/+page.svelte.
@MainActor
struct LabReglas: View {
    let modelo: ModeloRobot
    @State private var reglas: [Regla] = []
    @State private var tomadas: [Regla] = []
    @State private var evento = "tacto"
    @State private var eligiendo: (regla: Int, tipo: String)?
    @State private var error = ""
    @State private var aviso = ""
    @State private var guardando = false

    private let acciones: [(String, String)] = [
        ("reflejo", "Cara ya"), ("expresion", "Cara 3 s"), ("comportamiento", "Hace"), ("particula", "Le sale"), ("estado", "Siente"), ("led", "Luz"),
    ]
    private let leds = ["#FF6A33", "#FFB347", "#F3EEE8", "#4ADE80", "#3DE0FF", "#A78BFA", "#FF5FA2"]

    private var sucio: Bool { reglas != tomadas }
    private var configUsuario: String { modelo.config.paraDibujar }
    private func cuantas(_ e: String) -> Int { reglas.filter { $0.si == e }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            botonera
            ZStack(alignment: .bottomTrailing) {
                PantallaNucleo()
                    .aspectRatio(modelo.pantalla.redonda ? 1 : 320 / 172, contentMode: .fit)
                    .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                    .padding(14)
                    .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
                Button { simular() } label: { Label(NOMBRES_EVENTO[evento] ?? evento, systemImage: iconoEvento(evento)) }
                    .tecla(.naranja, chica: true).padding(10)
            }
            HStack {
                Text((NOMBRES_EVENTO[evento] ?? evento).uppercased()).font(Tipos.marca(22, .black)).foregroundStyle(Color.papel)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Button { nueva(nil) } label: { Image(systemName: "plus") }.tecla(.negra, cuadrada: true).disabled(reglas.count >= 24)
                    .accessibilityLabel("Respuesta nueva")
                Button { Task { await guardar() } } label: { Text(guardando ? "…" : aviso.isEmpty ? "Guardar" : aviso) }
                    .tecla(.naranja, chica: true).disabled(!sucio || guardando)
            }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) { tablero }
        }
        .onAppear {
            reglas = modelo.config.reglas
            tomadas = reglas
        }
        .onDisappear { modelo.pausarEspejo(0) }
    }

    private var botonera: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(64), spacing: 6), GridItem(.fixed(64), spacing: 6)], spacing: 6) {
                ForEach(EVENTOS, id: \.self) { e in
                    Button { evento = e; eligiendo = nil } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: iconoEvento(e)).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(evento == e ? Color.brasa : Color.gris)
                                Spacer(minLength: 0)
                                if cuantas(e) > 0 {
                                    Text("\(cuantas(e))").font(Tipos.marca(9, .black)).foregroundStyle(Color.tinta)
                                        .frame(minWidth: 16, minHeight: 16).background(Capsule().fill(Color.led))
                                }
                            }
                            Text(NOMBRES_EVENTO[e] ?? e).font(Tipos.marca(10.5, .bold)).lineLimit(2).minimumScaleFactor(0.8)
                                .foregroundStyle(evento == e ? Color.papel : Color.grisClaro)
                        }
                        .padding(9)
                        .frame(width: 108, height: 64, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.chapa))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(evento == e ? Color.brasa : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 140)
    }

    @ViewBuilder private var tablero: some View {
        let propias = reglas.indices.filter { reglas[$0].si == evento }
        let fabrica = VidaBase.reglas.filter { $0.si == evento }
        ForEach(propias, id: \.self) { i in fichaPropia(i) }
        ForEach(Array(fabrica.enumerated()), id: \.offset) { _, r in fichaFabrica(r) }
        if propias.isEmpty && fabrica.isEmpty {
            HStack {
                Grabado("Sin respuesta", color: Color.tinta.opacity(0.66))
                Spacer()
                Button { nueva(nil) } label: { Label("Respuesta", systemImage: "plus") }.tecla(.negra, chica: true)
            }
        }
    }

    private func fichaPropia(_ i: Int) -> some View {
        let r = reglas[i]
        return Bandeja {
            Flujo(espacio: 6, renglon: 6) {
                ForEach(Array(r.entonces.enumerated()), id: \.offset) { k, a in
                    Button { quitarAccion(i, k) } label: {
                        HStack(spacing: 6) {
                            ficha(a)
                            Image(systemName: "xmark").font(.system(size: 9, weight: .black)).foregroundStyle(Color.gris)
                        }
                        .padding(6).padding(.trailing, 4)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar \(a)")
                }
            }
            if r.entonces.count < 6 {
                Flujo(espacio: 6, renglon: 4) {
                    ForEach(acciones, id: \.0) { t, n in
                        Button {
                            if eligiendo?.regla == i && eligiendo?.tipo == t { eligiendo = nil } else { eligiendo = (i, t) }
                        } label: { Label(n, systemImage: "plus") }
                            .tecla(chica: true, hundida: eligiendo?.regla == i && eligiendo?.tipo == t)
                    }
                }
            }
            if let el = eligiendo, el.regla == i { selector(i, el.tipo) }
            HStack(spacing: 8) {
                CampoCondicion(valor: r.y ?? "") { t in
                    guard i < reglas.count else { return }
                    reglas[i].y = t.isEmpty ? nil : t
                }
                Button { quitar(i) } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Borrar")
            }
        }
    }

    private func fichaFabrica(_ r: Regla) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grabado("De fábrica" + (r.y.map { " · si \($0)" } ?? ""), color: Color.tinta.opacity(0.66))
            Flujo(espacio: 6, renglon: 6) {
                ForEach(Array(r.entonces.enumerated()), id: \.offset) { _, a in
                    ficha(a).padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido.opacity(0.6)))
                }
            }
            Button { nueva(r) } label: { Text("Copiar y cambiar") }.tecla(chica: true).disabled(reglas.count >= 24)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.tinta.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    @ViewBuilder private func ficha(_ a: String) -> some View {
        let partes = partirAccion(a)
        let tipo = partes.0
        let arg = partes.1
        HStack(spacing: 6) {
            switch tipo {
            case "reflejo", "expresion":
                MiniCara(nombre: arg, config: configUsuario, pantalla: modelo.pantalla, ancho: 40)
                Text(tipo == "expresion" ? "\(arg) · 3 s" : arg)
            case "comportamiento":
                Image(systemName: "play.fill")
                Text(arg.replacingOccurrences(of: "-", with: " "))
            case "particula":
                Text(GLIFO[arg] ?? arg).font(.system(size: 16))
                Text(arg)
            case "estado":
                let sube = arg.contains("+")
                let v = arg.prefix { $0.isLetter }
                Image(systemName: sube ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                Text(NOMBRES_ESTADO[String(v)] ?? String(v))
            case "led":
                Circle().fill(colorDe(arg.uppercased())).frame(width: 14, height: 14).shadow(color: colorDe(arg.uppercased()), radius: 4)
                Text("Luz")
            default:
                Image(systemName: "music.note")
                Text(arg)
            }
        }
        .font(Tipos.marca(11, .bold))
        .foregroundStyle(Color.papel)
        .lineLimit(1)
    }

    @ViewBuilder private func selector(_ i: Int, _ tipo: String) -> some View {
        switch tipo {
        case "reflejo", "expresion":
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VidaBase.nombresCaras, id: \.self) { c in
                        Button { sumar(i, tipo, c) } label: { MiniCara(nombre: c, config: configUsuario, pantalla: modelo.pantalla, ancho: 58) }
                            .buttonStyle(.plain)
                    }
                }
            }
        case "comportamiento":
            Chips(opciones: todosLosComportamientos, elegida: nil, texto: { $0.replacingOccurrences(of: "-", with: " ") }) { sumar(i, "comportamiento", $0) }
        case "particula":
            Chips(opciones: PARTICULAS, elegida: nil, texto: { GLIFO[$0] ?? $0 }) { sumar(i, "particula", $0) }
        case "estado":
            Flujo(espacio: 6, renglon: 4) {
                ForEach(ESTADO_VIDA, id: \.self) { v in
                    HStack(spacing: 4) {
                        Text((NOMBRES_ESTADO[v] ?? v).uppercased()).font(Tipos.marca(9.5, .heavy)).foregroundStyle(Color.tinta)
                        Button { sumar(i, "estado", "\(v)+0.2") } label: { Image(systemName: "arrowtriangle.up.fill") }.tecla(chica: true)
                        Button { sumar(i, "estado", "\(v)-0.2") } label: { Image(systemName: "arrowtriangle.down.fill") }.tecla(.negra, chica: true)
                    }
                }
            }
        default:
            HStack(spacing: 8) {
                ForEach(leds, id: \.self) { c in
                    Button { sumar(i, "led", c.lowercased()) } label: {
                        Circle().fill(colorDe(c)).frame(width: 30, height: 30).shadow(color: colorDe(c), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Luz \(c)")
                }
            }
        }
    }

    private var todosLosComportamientos: [String] {
        let base: [String] = VidaBase.comportamientos.keys.sorted()
        let propios: [String] = modelo.config.comportamientos.keys.filter { VidaBase.comportamientos[$0] == nil }.sorted()
        return base + propios
    }

    // MARK: Acciones

    private func nueva(_ desde: Regla?) {
        guard reglas.count < 24 else { return }
        reglas.append(desde ?? Regla(si: evento, entonces: ["reflejo:contento"]))
    }

    private func quitar(_ i: Int) {
        guard i < reglas.count else { return }
        reglas.remove(at: i)
        eligiendo = nil
    }

    private func sumar(_ i: Int, _ tipo: String, _ arg: String) {
        guard i < reglas.count, reglas[i].entonces.count < 6 else { return }
        reglas[i].entonces.append(unirAccion(tipo, arg))
        eligiendo = nil
    }

    private func quitarAccion(_ i: Int, _ k: Int) {
        guard i < reglas.count else { return }
        if reglas[i].entonces.count <= 1 { quitar(i); return }
        reglas[i].entonces.remove(at: k)
    }

    private func borrador() -> ConfigDoc {
        var c = modelo.config
        c.reglas = reglas
        return c
    }

    /// Le pasa el evento a la vista previa, con las reglas que se están armando.
    private func simular() {
        let c = borrador()
        if let e = Nucleo.validar(c.texto) { error = e; return }
        error = ""
        modelo.pausarEspejo(8)
        modelo.aplicarEnVistaPrevia(c.texto)
        if let i = EVENTOS.firstIndex(of: evento) { Nucleo.evento(i) }
    }

    private func guardar() async {
        guardando = true
        error = ""
        let e = await modelo.guardarAhora(borrador())
        guardando = false
        if let e { error = e; return }
        tomadas = reglas
        aviso = "Guardado"
        try? await Task.sleep(for: .seconds(2.5))
        aviso = ""
    }
}
