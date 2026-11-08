import SwiftUI

// Los módulos del paquete de vida (web/src/lib/consola/modulos): Habla,
// Cuidado, Jugar, el despertador de Su día, la ciudad para el clima y los
// avisos del celu en Reflejos.

/// Habla: cuánto habla solo (en un globo) y sus frases propias por situación.
struct ModHabla: View {
    let modelo: ModeloRobot
    @State private var situacion = "despertar"
    @State private var nueva = ""
    @State private var oido = ""

    private static let ejemplo: [String: String] = [
        "despertar": "¡Arriba, {dueno}!", "buenas-noches": "Hasta mañana, {dueno}", "volviste": "¡Volviste!", "te-extrane": "Te extrañé",
        "aburrido": "Qué embole...", "caricia": "Más, más", "saludo": "Hola, soy {robot}", "despertador": "¡Arriba!", "clima-lluvia": "Llevá paraguas",
    ]

    private func tono(_ v: Double) -> String { v <= 0.05 ? "Callado" : v >= 0.8 ? "Charlatán" : "Normal" }

    var body: some View {
        let c = modelo.config
        let frases = c.frasesPropias[situacion] ?? []
        let total = c.totalFrases
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Bandeja {
                    Perilla(nombre: "Cuánto", valor: c.frecuenciaHabla, mostrar: { tono($0) }, tamano: 64) { v in modelo.cambiar { $0.ponerFrecuenciaHabla(v) } }
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 130)
                Visor(relleno: 12) {
                    HStack {
                        Grabado("Cuando")
                        Spacer()
                        Text("\(total)/\(MAX_FRASES)").font(Tipos.marca(11, .heavy).monospacedDigit()).foregroundStyle(total >= MAX_FRASES ? Color.rojo : Color.gris)
                    }
                    Menu {
                        ForEach(SITUACIONES, id: \.self) { s in
                            let n = c.frasesPropias[s]?.count ?? 0
                            Button((NOMBRES_SITUACION[s] ?? s) + (n > 0 ? " · \(n)" : "")) { situacion = s }
                        }
                    } label: {
                        HStack {
                            Text(NOMBRES_SITUACION[situacion] ?? situacion).font(Tipos.marca(18, .black)).foregroundStyle(Color.papel).lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.gris)
                        }
                    }
                }
            }
            if frases.isEmpty {
                Bandeja { Text("Usa las suyas").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.7)) }
            }
            ForEach(Array(frases.enumerated()), id: \.offset) { i, f in
                Visor(relleno: 10) {
                    HStack(spacing: 8) {
                        Text("“\(f)”").font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(2)
                        Spacer(minLength: 0)
                        Button { probar(f) } label: { Image(systemName: "play.fill") }.tecla(chica: true).disabled(!modelo.conectado)
                            .accessibilityLabel("Que lo diga")
                        Button { quitar(i) } label: { Image(systemName: "xmark") }.tecla(.negra, chica: true).accessibilityLabel("Borrar")
                    }
                }
            }
            if !oido.isEmpty { AvisoConsola(texto: oido) }
            Visor(relleno: 12) {
                HStack(spacing: 8) {
                    TextField("", text: $nueva, prompt: Text(Self.ejemplo[situacion] ?? "Frase nueva").foregroundColor(Color(hex: 0x5A524A)))
                        .font(Tipos.marca(16, .black)).foregroundStyle(Color.papel).submitLabel(.done).onSubmit(agregar)
                        .onChange(of: nueva) { _, v in let x = cortarBytes(v, MAX_TEXTO); if x != v { nueva = x } }
                    Text("\(nueva.utf8.count)/\(MAX_TEXTO)").font(Tipos.marca(10, .heavy).monospacedDigit()).foregroundStyle(Color.gris)
                }
                HStack(spacing: 8) {
                    ForEach(["{dueno}", "{robot}"], id: \.self) { f in
                        Button { nueva = cortarBytes(nueva + f, MAX_TEXTO) } label: { Text(f) }.tecla(.negra, chica: true)
                    }
                    Spacer()
                    Button(action: agregar) { Label("Sumar", systemImage: "plus") }.tecla(.naranja, chica: true)
                        .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty || total >= MAX_FRASES)
                }
            }
        }
    }

    private func agregar() {
        let t = nueva.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, modelo.config.totalFrases < MAX_FRASES else { return }
        let s = situacion
        modelo.cambiar { c in c.ponerFrases(s, (c.frasesPropias[s] ?? []) + [t]) }
        nueva = ""
    }

    private func quitar(_ i: Int) {
        let s = situacion
        modelo.cambiar { c in
            var l = c.frasesPropias[s] ?? []
            if i < l.count { l.remove(at: i) }
            c.ponerFrases(s, l)
        }
    }

    private func probar(_ f: String) {
        let t = armarFrase(f, dueno: modelo.config.nombreDueno, robot: modelo.nombre)
        Task {
            oido = await modelo.decir(t) ?? "Lo dijo"
            try? await Task.sleep(for: .seconds(2))
            oido = ""
        }
    }
}

/// Cuidado: agua, pausa activa en el horario de trabajo, "¿cómo estás?", y por
/// Telegram que te extrañe y te cuente su día.
struct ModCuidado: View {
    let modelo: ModeloRobot

    var body: some View {
        let c = modelo.config.cuidado
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Bandeja {
                    Perilla(nombre: "Agua", valor: Double(c.agua), min: 0, max: 8, paso: 1, mostrar: { $0 < 0.5 ? "No" : "\(Int($0)) h" }, tamano: 64) { v in
                        modelo.cambiar { $0.cambiarCuidado { $0.agua = Int(v.rounded()) } }
                    }
                    .frame(maxWidth: .infinity)
                }
                .opacity(c.agua == 0 ? 0.7 : 1)
                Bandeja {
                    Perilla(nombre: "Pausa", valor: Double(c.pausa), min: 0, max: 240, paso: 15, mostrar: { $0 < 1 ? "No" : "\(Int($0))′" }, tamano: 64) { v in
                        modelo.cambiar { $0.cambiarCuidado { $0.ponerPausa(Int(v.rounded())) } }
                    }
                    .frame(maxWidth: .infinity)
                }
                .opacity(c.pausa == 0 ? 0.7 : 1)
            }
            Bandeja {
                Grabado("Trabajo", color: Color.tinta.opacity(0.66))
                HStack(spacing: 10) {
                    VisorMasMenos(rotulo: "Desde", valor: c.desde, chicos: true,
                                  menos: { modelo.cambiar { $0.cambiarCuidado { $0.moverTrabajo(desde: true, -30) } } },
                                  mas: { modelo.cambiar { $0.cambiarCuidado { $0.moverTrabajo(desde: true, 30) } } })
                    VisorMasMenos(rotulo: "Hasta", valor: c.hasta, chicos: true,
                                  menos: { modelo.cambiar { $0.cambiarCuidado { $0.moverTrabajo(desde: false, -30) } } },
                                  mas: { modelo.cambiar { $0.cambiarCuidado { $0.moverTrabajo(desde: false, 30) } } })
                }
                HStack(spacing: 5) {
                    ForEach(DIAS_SEMANA, id: \.letra) { d in
                        Button { modelo.cambiar { $0.cambiarCuidado { $0.alternarDia(d.letra) } } } label: { Text(d.letra) }
                            .buttonStyle(EstiloDia(prendido: c.diasTrabajo.contains(d.letra)))
                            .accessibilityLabel(d.nombre)
                    }
                }
            }
            Llave(texto: "¿Cómo estás?", prendida: c.animo, ancha: true) { modelo.cambiar { $0.cambiarCuidado { $0.animo.toggle() } } }
            HStack(spacing: 8) {
                Llave(texto: "Te extraña", prendida: c.extranar, ancha: true) { modelo.cambiar { $0.cambiarCuidado { $0.extranar.toggle() } } }
                Button { modelo.cambiar { $0.cambiarCuidado { $0.extranarDias = max(1, $0.extranarDias - 1) } } } label: { Image(systemName: "minus") }
                    .tecla(.negra, cuadrada: true).disabled(!c.extranar).accessibilityLabel("Un día menos")
                Text("\(c.extranarDias)d").font(Tipos.digitosChicos).foregroundStyle(c.extranar ? Color.brasa : Color(hex: 0x5A524A))
                    .frame(minWidth: 40).accessibilityLabel("\(c.extranarDias) días")
                Button { modelo.cambiar { $0.cambiarCuidado { $0.extranarDias = min(7, $0.extranarDias + 1) } } } label: { Image(systemName: "plus") }
                    .tecla(.negra, cuadrada: true).disabled(!c.extranar).accessibilityLabel("Un día más")
            }
            Llave(texto: "Resumen", prendida: c.resumen, ancha: true) { modelo.cambiar { $0.cambiarCuidado { $0.resumen.toggle() } } }
        }
    }
}

/// Jugar: cinco juegos en su pantalla y el marcador que guarda en su memoria.
struct ModJugar: View {
    let modelo: ModeloRobot
    @State private var memoria: Memoria?
    @State private var jugando: String?
    @State private var aviso = ""

    private func icono(_ j: String) -> String {
        switch j {
        case "ppt": "scissors"
        case "reflejos": "bolt.fill"
        case "mirada": "eye.fill"
        case "dado": "die.face.5.fill"
        default: "circle.circle"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(JUEGOS, id: \.self) { j in
                    Button { jugar(j) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: icono(j)).font(.system(size: 26, weight: .bold))
                            Text((NOMBRES_JUEGO[j] ?? j).uppercased()).font(Tipos.angosta(10, .black)).lineLimit(2).multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(jugando == j ? Color.papel : Color.tinta)
                        .frame(maxWidth: .infinity, minHeight: 92)
                    }
                    .buttonStyle(EstiloTeclaModulo(elegido: jugando == j))
                    .disabled(!modelo.conectado)
                    .accessibilityLabel(NOMBRES_JUEGO[j] ?? j)
                }
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                marcador("Jugados", memoria.map { "\($0.juegosJugados)" } ?? "—")
                marcador("Ganó", memoria.map { "\($0.juegosGanados)" } ?? "—")
                marcador("Hoy", memoria.map { "\($0.juegosHoy)" } ?? "—")
                marcador("Reflejo", reflejo)
            }
        }
        .task {
            guard modelo.esNube else { return }
            memoria = (try? await Cuenta.compartida.api.memoria(modelo.id))?.memoria
        }
    }

    private var reflejo: String {
        guard let m = memoria, m.mejorReflejo > 0 else { return "—" }
        return String(format: "%.2f s", Double(m.mejorReflejo) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    private func marcador(_ t: String, _ v: String) -> some View {
        Visor(relleno: 12) {
            Grabado(t)
            Digitos(texto: v, chicos: true)
        }
    }

    private func jugar(_ j: String) {
        guard jugando == nil else { return }
        jugando = j
        Task {
            aviso = await modelo.jugar(j) ?? "¡A jugar!"
            jugando = nil
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

/// El despertador (en Su día): uno solo; sin config se ve apagado y tocar algo lo prende.
struct BloqueDespertador: View {
    let modelo: ModeloRobot
    @State private var texto = ""
    @State private var probando = ""

    var body: some View {
        let d = modelo.config.despertadorVisible
        Bandeja {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Grabado("Despertador", color: Color.tinta.opacity(0.66))
                    Text(d.hora).font(Tipos.digitos).foregroundStyle(d.activo ? Color.tinta : Color.tinta.opacity(0.35))
                }
                Spacer()
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        boton("+1h") { mover(60) }
                        boton("+5′") { mover(5) }
                    }
                    HStack(spacing: 4) {
                        boton("−1h") { mover(-60) }
                        boton("−5′") { mover(-5) }
                    }
                }
            }
            HStack(spacing: 5) {
                ForEach(DIAS_SEMANA, id: \.letra) { x in
                    Button { modelo.cambiar { $0.cambiarDespertador { $0.alternar(x.letra) } } } label: { Text(x.letra) }
                        .buttonStyle(EstiloDia(prendido: d.todosLosDias.contains(x.letra)))
                        .accessibilityLabel(x.nombre)
                }
            }
            HStack(spacing: 8) {
                Llave(texto: "Activo", prendida: d.activo, ancha: true) {
                    let on = d.activo
                    modelo.cambiar { $0.cambiarDespertador { $0.activo = !on } }
                }
                Llave(texto: "Sonido", prendida: d.sonido, ancha: true) { modelo.cambiar { $0.cambiarDespertador { $0.sonido.toggle() } } }
            }
            VisorMasMenos(rotulo: "Posponer", valor: "\(d.posponer)′", chicos: true,
                          menos: { modelo.cambiar { $0.cambiarDespertador { $0.posponer = max(1, $0.posponer - 1) } } },
                          mas: { modelo.cambiar { $0.cambiarDespertador { $0.posponer = min(30, $0.posponer + 1) } } })
            CampoVisor(rotulo: "Dice", texto: $texto, ayuda: "¡Buen día!", claro: true) {
                let t = cortarBytes(texto.trimmingCharacters(in: .whitespaces), MAX_TEXTO)
                if t != (modelo.config.despertador?.texto ?? "") { modelo.cambiar { $0.cambiarDespertador { $0.texto = t } } }
            }
            .onChange(of: texto) { _, v in let x = cortarBytes(v, MAX_TEXTO); if x != v { texto = x } }
            Button { probar() } label: { Label(probando.isEmpty ? "Probar" : probando, systemImage: "alarm.fill") }
                .tecla(.naranja, ancha: true).disabled(!modelo.conectado)
        }
        .onAppear { texto = modelo.config.despertador?.texto ?? "" }
    }

    private func boton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Tipos.marca(11, .black)) }.tecla(.negra, chica: true)
    }

    private func mover(_ m: Int) { modelo.cambiar { $0.cambiarDespertador { $0.hora = sumarMinutos($0.hora, m) } } }

    private func probar() {
        probando = "…"
        Task {
            probando = await modelo.alarma("probar") ?? "Sonando"
            try? await Task.sleep(for: .seconds(3))
            probando = ""
        }
    }
}

/// Dónde vive, para el clima: un buscador de ciudad (lo busca la nube) y el tiempo de ahora.
struct BloqueUbicacion: View {
    let modelo: ModeloRobot
    @State private var buscando = false
    @State private var q = ""
    @State private var lugares: [Lugar] = []
    @State private var estado = "listo"  // listo, buscando, nada, error
    @State private var clima: ClimaAhora?
    @State private var reloj: Task<Void, Never>?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        let u = modelo.config.ubicacion
        Group {
            if !modelo.esNube {
                EmptyView()
            } else if let u, !buscando {
                Visor(relleno: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Grabado("Clima")
                            Text(u.ciudad.split(separator: ",").first.map(String.init) ?? u.ciudad).font(Tipos.marca(15, .black))
                                .foregroundStyle(Color.papel).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let c = clima {
                            Digitos(texto: "\(Int(c.temp.rounded()))°", chicos: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.descripcion).font(Tipos.chico).foregroundStyle(Color.hueso).lineLimit(1)
                                Text("↑\(c.max)° ↓\(c.min)°").font(Tipos.chico).foregroundStyle(Color.gris)
                            }
                        } else {
                            Text("--°").font(Tipos.digitosChicos).foregroundStyle(Color(hex: 0x5A524A))
                        }
                        Button { buscando = true } label: { Image(systemName: "magnifyingglass") }.tecla(.negra, cuadrada: true)
                            .accessibilityLabel("Cambiar la ciudad")
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Visor(relleno: 12) {
                        Grabado("Su ciudad")
                        HStack(spacing: 8) {
                            TextField("", text: $q, prompt: Text("Buscá tu ciudad").foregroundColor(Color(hex: 0x5A524A)))
                                .font(Tipos.marca(17, .black)).foregroundStyle(Color.papel).autocorrectionDisabled()
                                .onChange(of: q) { _, v in escribir(v) }
                                .onSubmit { if let l = lugares.first { elegir(l) } }
                            Led(estado: estado == "buscando" ? .on : estado == "listo" ? .apagado : .ambar)
                            if u != nil {
                                Button { buscando = false; q = ""; lugares = [] } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true)
                            }
                        }
                    }
                    ForEach(lugares) { l in
                        Button { elegir(l) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.nombre)
                                if !l.detalle.isEmpty { Text(l.detalle).font(Tipos.marca(10, .bold)).opacity(0.7) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tecla(ancha: true)
                    }
                    if estado == "nada" { Grabado("Nada con ese nombre", color: Color.tinta.opacity(0.7)) }
                }
            }
        }
        .task(id: u?.ciudad ?? "") {
            if u == nil { buscando = true }
            await cargarClima()
        }
    }

    private func escribir(_ v: String) {
        reloj?.cancel()
        let t = v.trimmingCharacters(in: .whitespaces)
        if t.utf8.count < 2 { lugares = []; estado = "listo"; return }
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            estado = "buscando"
            do {
                let l = try await api.buscarLugar(cortarBytes(t, 60))
                if q.trimmingCharacters(in: .whitespaces) != t { return }
                lugares = l
                estado = l.isEmpty ? "nada" : "listo"
            } catch {
                estado = "error"
            }
        }
    }

    private func elegir(_ l: Lugar) {
        let u = Ubicacion(lat: l.lat, lon: l.lon, ciudad: l.ciudad.isEmpty ? l.nombre : l.ciudad)
        modelo.cambiar { $0.ponerUbicacion(u) }
        buscando = false
        q = ""
        lugares = []
        clima = nil
        // La nube trae el clima apenas se guarda la ubicación.
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await cargarClima()
            try? await Task.sleep(for: .seconds(5.5))
            await cargarClima()
        }
    }

    private func cargarClima() async {
        guard modelo.esNube, modelo.config.ubicacion != nil else { return }
        clima = try? await api.clima(modelo.id)
    }
}

/// Los avisos del celu (en Reflejos): cómo reacciona a una notificación o
/// llamada según la app y el contacto.
struct AvisosDelCelu: View {
    let modelo: ModeloRobot

    var body: some View {
        let l = modelo.config.avisos
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Grabado("Del celu · \(l.count)/\(MAX_AVISOS)", color: Color.tinta.opacity(0.7))
                Spacer()
                Button {
                    modelo.cambiar { $0.avisos = $0.avisos + [AvisoCelu(tipo: "notificacion", expresion: "sorpresa", decir: "{app}")] }
                } label: { Label("Aviso", systemImage: "plus") }.tecla(.negra, chica: true).disabled(l.count >= MAX_AVISOS)
            }
            ForEach(Array(l.enumerated()), id: \.offset) { i, a in FichaAvisoCelu(modelo: modelo, indice: i, aviso: a) }
        }
    }
}

private struct FichaAvisoCelu: View {
    let modelo: ModeloRobot
    let indice: Int
    let aviso: AvisoCelu
    @State private var app = ""
    @State private var contacto = ""
    @State private var decir = ""

    private func poner(_ f: @escaping (inout AvisoCelu) -> Void) {
        let i = indice
        modelo.cambiar { c in
            var l = c.avisos
            guard i < l.count else { return }
            f(&l[i])
            c.avisos = l
        }
    }

    private var caras: [String] { (VidaBase.nombresCaras + modelo.config.expresiones.keys.filter { VidaBase.expresiones[$0] == nil }).sorted() }
    private var comportamientos: [String] {
        let base: [String] = Array(VidaBase.comportamientos.keys)
        let propios: [String] = Array(modelo.config.comportamientos.keys)
        return Array(Set(base + propios)).sorted()
    }

    var body: some View {
        Bandeja {
            HStack(spacing: 6) {
                Button { poner { $0.tipo = "notificacion" } } label: { Label("Notif.", systemImage: "bell.fill") }.tecla(chica: true, hundida: aviso.tipo == "notificacion")
                Button { poner { $0.tipo = "llamada" } } label: { Label("Llamada", systemImage: "phone.fill") }.tecla(chica: true, hundida: aviso.tipo == "llamada")
                Spacer()
                Button {
                    let i = indice
                    modelo.cambiar { c in var x = c.avisos; if i < x.count { x.remove(at: i) }; c.avisos = x }
                } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Borrar este aviso")
            }
            HStack(spacing: 8) {
                CampoVisor(rotulo: "App", texto: $app, ayuda: "Cualquiera", claro: true) { let v = app; poner { $0.app = cortarBytes(v.trimmingCharacters(in: .whitespaces), MAX_NOMBRE_AVISO) } }
                CampoVisor(rotulo: "Contacto", texto: $contacto, ayuda: "Cualquiera", claro: true) {
                    let v = contacto
                    poner { $0.contacto = cortarBytes(v.trimmingCharacters(in: .whitespaces), MAX_NOMBRE_AVISO) }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    Button("—") { poner { $0.expresion = "" } }
                    ForEach(caras, id: \.self) { c in Button(c) { poner { $0.expresion = c } } }
                } label: { selector(aviso.expresion.isEmpty ? "Cara —" : aviso.expresion) }
                Menu {
                    Button("—") { poner { $0.comportamiento = "" } }
                    ForEach(comportamientos, id: \.self) { c in Button(c.replacingOccurrences(of: "-", with: " ")) { poner { $0.comportamiento = c } } }
                } label: { selector(aviso.comportamiento.isEmpty ? "Hace —" : aviso.comportamiento.replacingOccurrences(of: "-", with: " ")) }
            }
            HStack(spacing: 8) {
                CampoVisor(rotulo: "Dice", texto: $decir, ayuda: "{app}", claro: true) {
                    let v = cortarBytes(decir.split(whereSeparator: \.isWhitespace).joined(separator: " "), MAX_DECIR_AVISO)
                    poner { $0.decir = v }
                }
                Llave(texto: "Sonido", prendida: aviso.sonido) { poner { $0.sonido.toggle() } }
            }
        }
        .onAppear { app = aviso.app; contacto = aviso.contacto; decir = aviso.decir }
    }

    private func selector(_ t: String) -> some View {
        HStack {
            Text(t).font(Tipos.marca(12, .bold)).foregroundStyle(Color.papel).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.gris)
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
    }
}
