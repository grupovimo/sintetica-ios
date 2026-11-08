import SwiftUI

// Los módulos simples de la consola (web/src/lib/consola/modulos).

/// Carácter: un dial con los 8 presets y una perilla por rasgo.
struct ModCaracter: View {
    let modelo: ModeloRobot

    var body: some View {
        let c = modelo.config
        let preset = c.preset
        let tocado = RASGOS.contains { r in abs(c.rasgo(r) - (rasgosDePreset(preset)[r] ?? 0.5)) > 0.001 }
        VStack(spacing: 20) {
            Dial(valor: preset) { p in modelo.cambiar { $0.ponerPreset(p) } }
                .frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                Grabado(tocado ? "Carácter · a tu medida" : "Carácter", color: Color.tinta.opacity(0.66))
                Text((NOMBRES_PRESET[preset] ?? preset).uppercased()).font(Tipos.marca(36, .black)).tracking(-1.4)
                    .foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                Text(DICE_PRESET[preset] ?? "").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
            }
            Bandeja(relleno: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 20) {
                    ForEach(RASGOS, id: \.self) { r in
                        Perilla(nombre: NOMBRES_RASGO[r] ?? r, valor: c.rasgo(r)) { v in modelo.cambiar { $0.ponerRasgo(r, v) } }
                    }
                }
            }
        }
    }
}

let COLORES_OJOS: [(hex: String, nombre: String)] = [
    ("#FF6A33", "Naranja"), ("#FFB347", "Ámbar"), ("#F3EEE8", "Blanco"), ("#4ADE80", "Verde"),
    ("#3DE0FF", "Cian"), ("#A78BFA", "Violeta"), ("#FF5FA2", "Rosa"), ("#FF3B3B", "Rojo"),
]

func colorDe(_ hex: String) -> Color {
    Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0xFF6A33)
}

/// Cara: el color y el tamaño de sus ojos, y ponerle una cara ya (o soltarla).
struct ModCara: View {
    let modelo: ModeloRobot
    @State private var error = ""

    private let rapidas: [(String, String)] = [
        ("contento", "Contento"), ("enamorado", "Enamorado"), ("guino", "Guiño"), ("sorpresa", "Sorpresa"),
        ("sospecha", "Sospecha"), ("pensando", "Pensando"), ("triste", "Triste"), ("enojado", "Enojado"),
        ("mareado", "Mareado"), ("dormido", "Dormido"), ("curioso", "Curioso"), ("glitch", "Glitch"),
    ]

    var body: some View {
        let c = modelo.config
        let conectado = modelo.conectado
        let fija = modelo.caraFija
        let visible = modelo.estado?.expresion ?? ""
        VStack(spacing: 16) {
            Bandeja {
                Grabado("Ojos", color: Color.tinta.opacity(0.66))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(COLORES_OJOS, id: \.hex) { o in lampara(o.hex, o.nombre, elegido: c.colorOjos == o.hex) }
                }
            }
            Bandeja {
                Perilla(nombre: "Tamaño", valor: c.tamano, min: 0.5, max: 1.5, mostrar: { "\(Int(($0 * 100).rounded()))%" }, tamano: 72) { v in
                    modelo.cambiar { $0.ponerTamano(v) }
                }
                .frame(maxWidth: .infinity)
            }
            Bandeja {
                HStack {
                    Grabado("Ya", color: Color.tinta.opacity(0.66))
                    Spacer()
                    Button { fijar("") } label: { Text(fija ? "Soltar" : "Se maneja solo") }.tecla(.negra, chica: true).disabled(!conectado || !fija)
                }
                Flujo(espacio: 8, renglon: 4) {
                    ForEach(rapidas, id: \.0) { n, t in
                        Button { fijar(n) } label: { Text(t) }.tecla(chica: true, hundida: fija && visible == n)
                    }
                }
                .disabled(!conectado)
                if !c.animaciones.isEmpty {
                    Grabado("Animaciones", color: Color.tinta.opacity(0.66))
                    Flujo(espacio: 8, renglon: 4) {
                        ForEach(c.animaciones, id: \.self) { n in
                            Button { Task { error = await modelo.comando(["reproducir": n]) ?? "" } } label: { Label(n, systemImage: "play.fill") }
                                .tecla(.negra, chica: true)
                        }
                    }
                    .disabled(!conectado)
                }
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            }
        }
    }

    private func lampara(_ hex: String, _ nombre: String, elegido: Bool) -> some View {
        let color = colorDe(hex)
        return Button { modelo.cambiar { $0.ponerColor(hex) } } label: {
            VStack(spacing: 8) {
                Circle().fill(color).frame(width: 22, height: 22).opacity(elegido ? 1 : 0.35)
                    .shadow(color: elegido ? color : .clear, radius: 7)
                Text(nombre.uppercased()).font(Tipos.marca(8.5, .heavy)).foregroundStyle(elegido ? Color.papel : Color.gris)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.8), radius: 3, y: 2))))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(elegido ? color : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ojos \(nombre)")
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
    }

    private func fijar(_ n: String) { Task { error = await modelo.comando(["expresion": n]) ?? "" } }
}

/// Su día: a qué hora se despierta y se duerme, y los cumpleaños que festeja.
struct ModDia: View {
    let modelo: ModeloRobot
    @State private var tuNombre = ""

    var body: some View {
        let c = modelo.config
        VStack(spacing: 16) {
            VisorMasMenos(rotulo: "Se despierta", valor: c.despierta,
                          menos: { modelo.cambiar { $0.moverHorario(despierta: true, minutos: -15) } },
                          mas: { modelo.cambiar { $0.moverHorario(despierta: true, minutos: 15) } })
            VisorMasMenos(rotulo: "Se duerme", valor: c.duerme,
                          menos: { modelo.cambiar { $0.moverHorario(despierta: false, minutos: -15) } },
                          mas: { modelo.cambiar { $0.moverHorario(despierta: false, minutos: 15) } })
            Bandeja(relleno: 12, espacio: 8) {
                BarraDia(despierta: c.despierta, duerme: c.duerme)
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                        Text(String(format: "%02d", h)).font(Tipos.marca(10, .heavy).monospacedDigit()).foregroundStyle(Color.tinta.opacity(0.66))
                        if h < 24 { Spacer() }
                    }
                }
            }
            CampoVisor(rotulo: "Vos te llamás", texto: $tuNombre, ayuda: "Tu nombre", claro: true) {
                let n = tuNombre
                if n != modelo.config.nombreDueno { modelo.cambiar { $0.ponerNombreDueno(n) } }
            }
            .onChange(of: tuNombre) { _, v in let x = cortarBytes(v, 24); if x != v { tuNombre = x } }
            SelectorCumple(rotulo: "Tu cumple", valor: c.cumpleDueno) { m, d in modelo.cambiar { $0.ponerCumple(robot: false, mes: m, dia: d) } }
            SelectorCumple(rotulo: "Su cumple", valor: c.cumpleRobot) { m, d in modelo.cambiar { $0.ponerCumple(robot: true, mes: m, dia: d) } }
        }
        .onAppear { tuNombre = modelo.config.nombreDueno }
    }
}

/// La barra de 24 h: dónde está despierto (puede cruzar la medianoche) y ahora.
struct BarraDia: View {
    let despierta: String
    let duerme: String

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GeometryReader { g in
                let w = g.size.width
                let a = Double(aMinutos(despierta)) / 1440, z = Double(aMinutos(duerme)) / 1440
                let tramos: [(Double, Double)] = a < z ? [(a, z)] : [(0, z), (a, 1)]
                let cal = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
                let ahora = Double((cal.hour ?? 0) * 60 + (cal.minute ?? 0)) / 1440
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.8), radius: 4, y: 2)))
                    ForEach(Array(tramos.enumerated()), id: \.offset) { _, t in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Color.brasa, Color(hex: 0xF2541A)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Color.led.opacity(0.6), radius: 6)
                            .frame(width: max(0, (t.1 - t.0) * w), height: 24)
                            .offset(x: t.0 * w)
                    }
                    Rectangle().fill(Color.papel).frame(width: 3, height: 34).shadow(color: .white, radius: 4).offset(x: ahora * w - 1.5)
                }
            }
        }
        .frame(height: 34)
        .accessibilityLabel("Despierto de \(despierta) a \(duerme)")
    }
}

/// Día y mes (para los cumpleaños).
struct SelectorCumple: View {
    let rotulo: String
    let valor: String?
    let alCambiar: (Int, Int) -> Void

    var body: some View {
        let p = partesCumple(valor)
        Visor(relleno: 12) {
            Grabado(rotulo)
            HStack(spacing: 10) {
                Menu {
                    Button("—") { alCambiar(0, 0) }
                    ForEach(1 ... 31, id: \.self) { d in Button("\(d)") { alCambiar(p.mes == 0 ? 1 : p.mes, d) } }
                } label: { etiqueta(p.dia == 0 ? "—" : "\(p.dia)") }
                Menu {
                    Button("—") { alCambiar(0, 0) }
                    ForEach(1 ... 12, id: \.self) { m in Button(MESES[m - 1]) { alCambiar(m, p.dia == 0 ? 1 : p.dia) } }
                } label: { etiqueta(p.mes == 0 ? "—" : MESES[p.mes - 1]) }
                Spacer()
            }
        }
    }

    private func etiqueta(_ t: String) -> some View {
        HStack(spacing: 6) {
            Text(t).font(Tipos.marca(18, .black))
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.gris)
        }
        .foregroundStyle(Color.papel)
    }
}

/// Modos: qué es el robot ahora. Compañía (se maneja solo), reloj o pomodoro.
struct ModModos: View {
    let modelo: ModeloRobot

    private let modos: [(clave: String, nombre: String, icono: String, listo: Bool)] = [
        ("mascota", "Compañía", "heart.fill", true), ("reloj", "Reloj", "clock.fill", true), ("pomodoro", "Pomodoro", "timer", true),
        ("clima", "Clima", "cloud.sun.fill", false), ("notificaciones", "Avisos", "bell.fill", false),
    ]

    var body: some View {
        let c = modelo.config
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(modos, id: \.clave) { m in
                    Button { modelo.cambiar { $0.ponerModo(m.clave) } } label: { tecla(m.nombre, m.icono, elegido: c.modo == m.clave, listo: m.listo) }
                        .buttonStyle(EstiloTeclaModulo(elegido: c.modo == m.clave))
                        .disabled(!m.listo)
                        .opacity(m.listo ? 1 : 0.55)
                        .accessibilityAddTraits(c.modo == m.clave ? [.isSelected] : [])
                }
            }
            if c.modo == "pomodoro" {
                VisorMasMenos(rotulo: "Foco", valor: String(format: "%02d min", c.trabajo),
                              menos: { modelo.cambiar { $0.moverPomodoro(trabajo: true, -5) } },
                              mas: { modelo.cambiar { $0.moverPomodoro(trabajo: true, 5) } })
                VisorMasMenos(rotulo: "Descanso", valor: String(format: "%02d min", c.descanso),
                              menos: { modelo.cambiar { $0.moverPomodoro(trabajo: false, -1) } },
                              mas: { modelo.cambiar { $0.moverPomodoro(trabajo: false, 1) } })
                Label("Un toque arranca o pausa", systemImage: "hand.tap.fill").font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8))
            }
        }
    }

    private func tecla(_ nombre: String, _ icono: String, elegido: Bool, listo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(elegido ? Color.led : Color.grisClaro).frame(width: 9, height: 9).shadow(color: elegido ? Color.led : .clear, radius: 5)
                Spacer()
                if !listo {
                    Text("PRONTO").font(Tipos.marca(8.5, .heavy)).tracking(1).padding(.horizontal, 6).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.tinta.opacity(0.12)))
                }
            }
            Image(systemName: icono).font(.system(size: 22, weight: .semibold))
            Text(nombre.uppercased()).font(Tipos.marca(15, .black)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(elegido ? Color.papel : Color.tinta)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }
}

/// Voz: para los modelos con micrófono o parlante.
struct ModVoz: View {
    let modelo: ModeloRobot
    @State private var palabra = ""

    private let tipos: [(String, String)] = [("grave", "Grave"), ("media", "Media"), ("aguda", "Aguda"), ("robot", "Robot")]

    var body: some View {
        let m = modelo.producto
        let habla = m.tiene(.parlante), escucha = m.tiene(.microfono)
        let v = modelo.config.voz
        if !habla && !escucha {
            Bandeja {
                HStack(spacing: 18) {
                    Image(systemName: "lock.fill").font(.system(size: 34, weight: .bold))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIN VOZ").font(Tipos.marca(20, .black))
                        Text("Llega con los que hablan.").font(Tipos.texto).opacity(0.75)
                    }
                }
                .foregroundStyle(Color.tinta)
            }
        } else {
            VStack(spacing: 16) {
                Bandeja {
                    HStack(spacing: 24) {
                        if habla {
                            Perilla(nombre: "Volumen", valor: (v["volumen"] as? NSNumber)?.doubleValue ?? 0.7) { x in modelo.cambiar { $0.ponerVoz("volumen", x) } }
                        }
                        if escucha {
                            Perilla(nombre: "Oído", valor: (v["microfono"] as? NSNumber)?.doubleValue ?? 0.6) { x in modelo.cambiar { $0.ponerVoz("microfono", x) } }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if habla {
                        Grabado("Su voz", color: Color.tinta.opacity(0.66))
                        Flujo(espacio: 8, renglon: 4) {
                            ForEach(tipos, id: \.0) { k, t in
                                Button { modelo.cambiar { $0.ponerVoz("tipo", k) } } label: { Text(t) }
                                    .tecla(chica: true, hundida: (v["tipo"] as? String ?? "media") == k)
                            }
                        }
                    }
                }
                if escucha {
                    CampoVisor(rotulo: "Responde a", texto: $palabra, ayuda: modelo.nombre) {
                        let t = cortarBytes(palabra.trimmingCharacters(in: .whitespaces), 16)
                        modelo.cambiar { $0.ponerVoz("palabra", t.isEmpty ? nil : t) }
                    }
                    .onChange(of: palabra) { _, x in let c = cortarBytes(x, 16); if c != x { palabra = c } }
                    Llave(texto: "Conversar con IA", prendida: v["conversar"] as? Bool ?? false, ancha: true) {
                        let si = !(modelo.config.voz["conversar"] as? Bool ?? false)
                        modelo.cambiar { $0.ponerVoz("conversar", si) }
                    }
                    Text("“\(palabra.isEmpty ? modelo.nombre : palabra), ¿qué hora es?”").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
                }
            }
            .onAppear { palabra = modelo.config.voz["palabra"] as? String ?? "" }
        }
    }
}
