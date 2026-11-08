import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// Los módulos de la v1.9 (web/src/lib/consola/modulos): Amigos, Hábitos,
// Agenda y Avisos de afuera. Son de la nube: sin cuenta, quedan bloqueados.

/// Lo que muestran los módulos de la nube si el robot no está en la cuenta.
struct SoloNube: View {
    var body: some View {
        Bandeja {
            HStack(spacing: 16) {
                Image(systemName: "icloud.slash.fill").font(.system(size: 30, weight: .bold))
                Text("SOLO CON LA NUBE").font(Tipos.marca(18, .black))
            }
            .foregroundStyle(Color.tinta)
        }
    }
}

/// Un QR (CoreImage), negro sobre papel.
func imagenQR(_ texto: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(texto.utf8)
    f.correctionLevel = "M"
    guard let s = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
          let cg = CIContext().createCGImage(s, from: s.extent) else { return nil }
    return UIImage(cgImage: cg)
}

private let NOMBRE_TOQUE: [String: String] = ["toque": "Toque", "abrazo": "Abrazo", "beso": "Beso", "carita": "Carita"]
private let SIMBOLO_TOQUE: [String: String] = ["toque": "hand.point.up.left.fill", "abrazo": "figure.2.arms.open", "beso": "heart.fill", "carita": "face.smiling.inverse"]
private let CARITAS = ["contento", "risa", "enamorado", "guino", "sorpresa", "triste", "orgulloso", "pensando"]

/// Amigos: invitar con un código (o el QR), aceptar el de otro y mandarle
/// toques a sus robots. Cada amigo elige cuáles de mis robots reciben los suyos.
@MainActor
struct ModAmigos: View {
    let modelo: ModeloRobot
    @State private var amigos: [Amigo] = []
    @State private var mios: [RobotNube] = []
    @State private var invitacion: Invitacion?
    @State private var qr: UIImage?
    @State private var codigo = ""
    @State private var error = ""
    @State private var aviso = ""
    @State private var carita: [Int: String] = [:]
    @State private var mandando = ""
    @State private var copiado = false
    @State private var borrar: Amigo?
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        if !modelo.esNube {
            SoloNube()
        } else {
            VStack(spacing: 14) {
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                invitar
                aceptar
                if !aviso.isEmpty { AvisoConsola(texto: aviso) }
                if amigos.isEmpty {
                    Bandeja { Grabado("Sin amigos todavía", color: Color.tinta.opacity(0.66)) }
                }
                ForEach(amigos) { a in ficha(a) }
            }
            .task { await cargar() }
            .task { mios = (try? await api.robots()) ?? [] }
            .onAppear { oyente = EnVivo.compartido.escuchar { e in if e.tipo == "toque" { Task { await cargar() } } } }
            .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
            .confirmationDialog("¿Dejar de ser amigos?", isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } }), titleVisibility: .visible) {
                Button("Dejar", role: .destructive) { if let a = borrar { Task { try? await api.borrarAmigo(a.id); await cargar() } } }
            }
        }
    }

    private func cargar() async {
        do { amigos = try await api.amigos() } catch { self.error = error.localizedDescription }
    }

    private var invitar: some View {
        Bandeja {
            if let inv = invitacion {
                HStack(alignment: .center, spacing: 14) {
                    if let qr {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 110, height: 110)
                            .padding(8).background(RoundedRectangle(cornerRadius: 14).fill(Color.papel))
                            .accessibilityLabel("QR para sumarte de amigo")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Grabado("Tu código · \(horasQueVence(inv.vence)) h", color: Color.tinta.opacity(0.66))
                        Digitos(texto: inv.codigoLindo, chicos: true)
                        HStack(spacing: 6) {
                            Button {
                                UIPasteboard.general.string = inv.link
                                copiado = true
                                Task { try? await Task.sleep(for: .seconds(1.8)); copiado = false }
                            } label: { Text(copiado ? "Copiado" : "Copiar") }.tecla(.naranja, chica: true)
                            if let u = URL(string: inv.link) {
                                ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.tecla(.negra, cuadrada: true)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "figure.2.arms.open").font(.system(size: 34, weight: .bold)).foregroundStyle(Color.tinta)
                    Spacer()
                    Button { Task { await crearInvitacion() } } label: { Text("Invitar") }.tecla(.naranja)
                }
            }
        }
    }

    private func horasQueVence(_ d: Date?) -> Int { max(0, Int(((d ?? Date()).timeIntervalSinceNow / 3600).rounded())) }

    private func crearInvitacion() async {
        error = ""
        do {
            let i = try await api.invitarAmigo()
            invitacion = i
            qr = imagenQR(i.link)
        } catch { self.error = error.localizedDescription }
    }

    private var aceptar: some View {
        Visor(relleno: 12) {
            Grabado("Código de un amigo")
            HStack(spacing: 8) {
                TextField("", text: $codigo, prompt: Text("ABCD-EFGH").foregroundColor(Color(hex: 0x5A524A)))
                    .font(Tipos.marca(22, .black)).foregroundStyle(Color.brasa)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onSubmit { Task { await aceptarCodigo() } }
                Button { Task { await aceptarCodigo() } } label: { Text("Aceptar") }.tecla(.naranja, chica: true)
                    .disabled(limpiarCodigo(codigo).isEmpty)
            }
        }
    }

    private func aceptarCodigo() async {
        let c = limpiarCodigo(codigo)
        guard !c.isEmpty else { return }
        error = ""
        do {
            let a = try await api.aceptarAmigo(c)
            codigo = ""
            decir("¡Ya son amigos con \(a.nombre)!")
            await cargar()
        } catch let e as ErrorApi {
            error = e.estado == 409 ? "Ya son amigos" : e.estado == 400 ? "Ese código no anda" : e.mensaje
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decir(_ t: String) {
        aviso = t
        Task { try? await Task.sleep(for: .seconds(2.5)); if aviso == t { aviso = "" } }
    }

    private func ficha(_ a: Amigo) -> some View {
        Bandeja {
            HStack(spacing: 10) {
                Led(estado: a.conectado ? .verde : .apagado)
                Text(a.nombre.uppercased()).font(Tipos.marca(18, .black)).foregroundStyle(Color.tinta).lineLimit(1)
                Spacer()
                Button { borrar = a } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true).accessibilityLabel("Dejar de ser amigos")
            }
            HStack(spacing: 8) {
                ForEach(TIPOS_TOQUE, id: \.self) { t in
                    Button { Task { await tocar(a, t) } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: SIMBOLO_TOQUE[t] ?? "hand.point.up.left.fill").font(.system(size: 22, weight: .bold))
                            Text((NOMBRE_TOQUE[t] ?? t).uppercased()).font(Tipos.angosta(10, .black)).lineLimit(1)
                        }
                        .foregroundStyle(mandando == "\(a.id):\(t)" ? Color.papel : Color.tinta)
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(EstiloTeclaModulo(elegido: mandando == "\(a.id):\(t)"))
                    .accessibilityLabel(NOMBRE_TOQUE[t] ?? t)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CARITAS, id: \.self) { c in
                        let sel = (carita[a.id] ?? "contento") == c
                        Button { carita[a.id] = c } label: {
                            MiniCara(nombre: c, config: nil, pantalla: Pantalla(), ancho: 52)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(sel ? Color.tinta : Color.clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(c)
                        .accessibilityAddTraits(sel ? [.isSelected] : [])
                    }
                }
            }
            if !mios.isEmpty {
                Grabado("Le llega a", color: Color.tinta.opacity(0.66))
                Flujo(espacio: 6, renglon: 6) {
                    ForEach(mios) { r in
                        Llave(texto: r.apodo.isEmpty ? (r.estado?.nombre ?? String(r.id.suffix(4))) : r.apodo, prendida: a.recibe(r.id)) {
                            Task { await robots(a, r.id) }
                        }
                    }
                    if mios.count > 1 { Llave(texto: "Todos", prendida: a.todos) { Task { await robots(a, nil) } } }
                }
            }
        }
    }

    private func tocar(_ a: Amigo, _ tipo: String) async {
        guard mandando.isEmpty else { return }
        mandando = "\(a.id):\(tipo)"
        do {
            let r = try await api.tocarAmigo(a.id, tipo: tipo, expresion: tipo == "carita" ? (carita[a.id] ?? "contento") : nil, desde: modelo.id)
            decir(r.robots > 0 ? "¡Le llegó!" : r.telegram ? "Le llegó por Telegram" : "Le llega cuando se conecte")
        } catch let e as ErrorApi {
            decir(e.estado == 429 ? "Muchos toques: esperá un rato" : e.mensaje)
        } catch {
            decir("No pude")
        }
        try? await Task.sleep(for: .milliseconds(300))
        mandando = ""
    }

    private func robots(_ a: Amigo, _ id: String?) async {
        let l = Amigo.robotsCon(a, alternando: id, mios: mios.map(\.id))
        do { try await api.robotsDeAmigo(a.id, l); await cargar() } catch { self.error = error.localizedDescription }
    }
}

/// Hábitos: hasta 4, cada uno con su ícono, la hora a la que pregunta y sus
/// días. La tecla grande lo marca hecho hoy; abajo, la racha y 60 días en puntitos.
@MainActor
struct ModHabitos: View {
    let modelo: ModeloRobot
    @State private var vistas: [VistaHabito] = []
    @State private var aviso = ""

    var body: some View {
        let l = modelo.config.habitos
        VStack(spacing: 14) {
            ForEach(Array(l.enumerated()), id: \.offset) { i, h in FichaHabito(modelo: modelo, indice: i, habito: h, vista: vista(i, h)) { marcar(i) } }
            if l.count < MAX_HABITOS {
                Button { modelo.cambiar { $0.habitos = $0.habitos + [Habito.nuevo(usados: $0.habitos)] } } label: { Label("Hábito", systemImage: "plus") }
                    .tecla(.negra, ancha: true)
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso) }
        }
        .task(id: modelo.versionConfig) { await cargar() }
    }

    private func vista(_ i: Int, _ h: Habito) -> VistaHabito? { vistas.first { $0.indice == i && $0.nombre == h.nombre } }

    private func cargar() async {
        guard modelo.esNube else { return }
        if let v = try? await Cuenta.compartida.api.habitos(modelo.id) { vistas = v }
    }

    private func marcar(_ i: Int) {
        let h = modelo.config.habitos
        guard i < h.count else { return }
        let hecho = !(vista(i, h[i])?.hoy ?? false)
        Task {
            do {
                let v = try await Cuenta.compartida.api.marcarHabito(modelo.id, i, hecho: hecho)
                if let k = vistas.firstIndex(where: { $0.indice == i }) { vistas[k] = v } else { vistas.append(v) }
                aviso = hecho ? (v.racha >= 3 ? "¡\(v.racha) días seguidos!" : "¡Bien ahí!") : "Desmarcado"
            } catch let e as ErrorApi {
                aviso = e.estado == 404 ? "Guardando… probá en un segundo" : "No pude"
            } catch {
                aviso = "No pude"
            }
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

private struct FichaHabito: View {
    let modelo: ModeloRobot
    let indice: Int
    let habito: Habito
    let vista: VistaHabito?
    let marcar: () -> Void
    @State private var nombre = ""

    private func poner(_ f: @escaping (inout Habito) -> Void) {
        let i = indice
        modelo.cambiar { c in
            var l = c.habitos
            guard i < l.count else { return }
            f(&l[i])
            c.habitos = l
        }
    }

    private var hora: Binding<Date> {
        Binding(get: {
            let m = aMinutos(habito.hora.isEmpty ? "09:00" : habito.hora)
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            let h = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            poner { $0.hora = h }
        })
    }

    var body: some View {
        let hoy = vista?.hoy ?? false
        let racha = vista?.racha ?? 0
        Bandeja {
            HStack(alignment: .top, spacing: 12) {
                Button(action: marcar) {
                    Image(systemName: SIMBOLO_HABITO[habito.icono] ?? "star.fill").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(hoy ? Color.brasa : Color.tinta)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(RadialGradient(colors: hoy ? [Color(hex: 0x3A3632), Color(hex: 0x151310)] : [Color(hex: 0xFBF9F5), Color(hex: 0xDDD6CA)],
                                                                 center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 50)))
                        .background(Circle().fill(Color(hex: 0x8F887C)).offset(y: hoy ? 1 : 6))
                        .offset(y: hoy ? 5 : 0)
                        .overlay(alignment: .topTrailing) { Led(estado: hoy ? .on : .apagado).padding(8) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habito.nombre): \(hoy ? "hecho hoy" : "marcar hecho")")
                .sensoryFeedback(.success, trigger: hoy)
                VStack(alignment: .leading, spacing: 8) {
                    CampoVisor(rotulo: "Nombre", texto: $nombre, ayuda: "Agua", claro: true) {
                        let t = cortarBytes(nombre.trimmingCharacters(in: .whitespaces), MAX_NOMBRE_HABITO)
                        if t.isEmpty { nombre = habito.nombre } else if t != habito.nombre { poner { $0.nombre = t } }
                    }
                    .onChange(of: nombre) { _, v in let x = cortarBytes(v, MAX_NOMBRE_HABITO); if x != v { nombre = x } }
                    HStack(spacing: 6) {
                        Digitos(texto: "\(racha)", chicos: true)
                        Grabado(racha == 1 ? "día" : "días", color: Color.tinta.opacity(0.66))
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    let i = indice
                    modelo.cambiar { c in var l = c.habitos; if i < l.count { l.remove(at: i) }; c.habitos = l }
                } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true).accessibilityLabel("Quitar \(habito.nombre)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ICONOS_HABITO, id: \.self) { ic in
                        Button { poner { $0.icono = ic } } label: { Image(systemName: SIMBOLO_HABITO[ic] ?? "star.fill") }
                            .tecla(chica: true, hundida: habito.icono == ic).accessibilityLabel(ic)
                    }
                }
            }
            HStack(spacing: 8) {
                Llave(texto: "Pregunta", prendida: !habito.hora.isEmpty) { poner { $0.hora = $0.hora.isEmpty ? "09:00" : "" } }
                if !habito.hora.isEmpty {
                    DatePicker("", selection: hora, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact).tint(Color.brasa).colorScheme(.dark)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                ForEach(DIAS_SEMANA, id: \.letra) { d in
                    Button { poner { $0.alternar(d.letra) } } label: { Text(d.letra) }
                        .buttonStyle(EstiloDia(prendido: habito.todosLosDias.contains(d.letra)))
                        .accessibilityLabel(d.nombre)
                }
            }
            Puntitos(dias: vista?.dias ?? [])
        }
        .onAppear { nombre = habito.nombre }
        .onChange(of: habito.nombre) { _, v in nombre = v }
    }
}

/// Los últimos 60 días en puntitos (el de hoy, marcado).
private struct Puntitos: View {
    let dias: Set<String>
    var body: some View {
        let l = ultimosDias(60)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 20), spacing: 3) {
            ForEach(Array(l.enumerated()), id: \.offset) { k, d in
                Circle().fill(dias.contains(d) ? Color.tinta : Color.tinta.opacity(0.18))
                    .frame(height: 9)
                    .overlay(Circle().stroke(k == l.count - 1 ? Color.papel : Color.clear, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Últimos 60 días: \(l.filter { dias.contains($0) }.count) hechos")
    }
}

/// Agenda: tu calendario (la dirección secreta iCal de Google Calendar o
/// cualquier .ics). Unos minutos antes te avisa con su cara de apuro; a la noche, lo de mañana.
@MainActor
struct ModAgenda: View {
    let modelo: ModeloRobot
    @Environment(\.openURL) private var abrir
    @State private var agenda: Agenda?
    @State private var ics = ""
    @State private var error = ""
    @State private var conectando = false
    @State private var reloj: Task<Void, Never>?
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }
    private static let semana = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    var body: some View {
        if !modelo.esNube {
            SoloNube()
        } else {
            VStack(spacing: 14) {
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                if let a = agenda {
                    if a.conectada { conectada(a) } else { pasos }
                } else {
                    Grabado("Buscando…", color: Color.tinta.opacity(0.66))
                }
            }
            .task { await cargar() }
            .onAppear { oyente = EnVivo.compartido.escuchar { e in if e.tipo == "agenda" { Task { await cargar() } } } }
            .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
        }
    }

    private func cargar() async {
        do { agenda = try await api.agenda() } catch { self.error = error.localizedDescription }
    }

    private var pasos: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                paso(1, "gearshape.fill", "Configuración")
                paso(2, "calendar", "Tu calendario")
                paso(3, "lock.fill", "Dirección secreta iCal")
            }
            Button { if let u = URL(string: "https://calendar.google.com/calendar/r/settings") { abrir(u) } } label: {
                Label("Google Calendar", systemImage: "arrow.up.right.square")
            }
            .tecla(.negra, chica: true)
            Visor(relleno: 12) {
                Grabado("Pegala acá")
                HStack(spacing: 8) {
                    TextField("", text: $ics, prompt: Text("https://…/basic.ics").foregroundColor(Color(hex: 0x5A524A)))
                        .font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { Task { await conectar() } } label: { Text(conectando ? "…" : "Conectar") }.tecla(.naranja, chica: true)
                        .disabled(ics.trimmingCharacters(in: .whitespaces).isEmpty || conectando)
                }
            }
        }
    }

    private func paso(_ n: Int, _ icono: String, _ t: String) -> some View {
        Bandeja(relleno: 10, espacio: 8) {
            Text("\(n)").font(Tipos.marca(12, .black)).foregroundStyle(Color.tinta.opacity(0.55))
            Image(systemName: icono).font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.tinta).frame(maxWidth: .infinity)
            Text(t.uppercased()).font(Tipos.angosta(10, .black)).foregroundStyle(Color.tinta).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
        }
    }

    private func conectar() async {
        let u = ics.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty, !conectando else { return }
        conectando = true
        error = ""
        do {
            agenda = try await api.conectarAgenda(u)
            ics = ""
        } catch let e as ErrorApi {
            error = e.detalle.isEmpty ? e.mensaje : "\(e.mensaje): \(e.detalle)"
        } catch {
            self.error = error.localizedDescription
        }
        conectando = false
    }

    private func conectada(_ a: Agenda) -> some View {
        VStack(spacing: 12) {
            Bandeja {
                HStack(spacing: 10) {
                    Led(estado: a.error.isEmpty ? .verde : .ambar)
                    VStack(alignment: .leading, spacing: 4) {
                        Grabado(a.error.isEmpty ? "Conectada" : "No la pude leer", color: Color.tinta.opacity(0.66))
                        Text(a.ics).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Color.tinta.opacity(0.8))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Button { Task { try? await api.sacarAgenda(); await cargar() } } label: { Text("Sacar") }.tecla(.negra, chica: true)
                }
            }
            Bandeja {
                Perilla(nombre: "Avisa", valor: Double(a.aviso), min: 0, max: 15, paso: 1, mostrar: { $0 < 0.5 ? "A la hora" : "\(Int($0))′ antes" }, tamano: 60) { v in
                    ponerAviso(Int(v.rounded()))
                }
                .frame(maxWidth: .infinity)
            }
            if a.proximos.isEmpty {
                Visor(relleno: 12) { Grabado("Nada en dos semanas") }
            }
            ForEach(a.proximos) { e in evento(e) }
        }
    }

    private func evento(_ e: EventoAgenda) -> some View {
        let d = e.fecha ?? Date()
        let cal = Calendar.current
        let dia = cal.component(.weekday, from: d) - 1
        let hoy = cal.isDateInToday(d)
        return Visor(relleno: 10) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Grabado(ModAgenda.semana[max(0, min(6, dia))], color: hoy ? .brasa : .gris)
                    Digitos(texto: "\(cal.component(.day, from: d))", chicos: true)
                }
                .frame(width: 48)
                Text(e.titulo).font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(2)
                Spacer(minLength: 0)
                Text(e.todoElDia ? "Todo el día" : (e.inicio.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    .font(Tipos.chico).foregroundStyle(Color.grisClaro)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(hoy ? Color.brasa : Color.clear, lineWidth: 2))
    }

    private func ponerAviso(_ v: Int) {
        agenda?.aviso = v
        reloj?.cancel()
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            try? await api.avisoAgenda(v)
        }
    }
}

/// Avisos de afuera: una dirección secreta para pegar en GitHub, Mercado Pago o
/// donde quieras. Cuando llega algo, tus robots te avisan con su cara.
@MainActor
struct ModAvisos: View {
    let modelo: ModeloRobot
    @State private var e: Entrantes?
    @State private var error = ""
    @State private var copiado = ""
    @State private var seguro = false
    @State private var mp = ""
    @State private var ultimo = ""
    @State private var probado: [String: String] = [:]
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        if !modelo.esNube {
            SoloNube()
        } else {
            VStack(spacing: 14) {
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                direccion
                servicios
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(TIPOS_ENTRANTE, id: \.self) { t in tipo(t) }
                }
            }
            .task { await cargar() }
            .onAppear { oyente = EnVivo.compartido.escuchar { x in if x.tipo == "entrante" { ultimo = x.datos["tipo"] as? String ?? "" } } }
            .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
        }
    }

    private func cargar() async {
        do { e = try await api.entrantes() } catch { self.error = error.localizedDescription }
    }

    private func copiar(_ t: String, _ que: String) {
        UIPasteboard.general.string = t
        copiado = que
        Task { try? await Task.sleep(for: .seconds(1.8)); if copiado == que { copiado = "" } }
    }

    private var direccion: some View {
        Bandeja {
            Grabado("Tu dirección secreta", color: Color.tinta.opacity(0.66))
            if let u = e?.url, !u.isEmpty {
                Button { copiar(u, "url") } label: {
                    HStack {
                        Text(u).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.brasa)
                            .lineLimit(2).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Grabado(copiado == "url" ? "Copiada" : "Copiar")
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
                }
                .buttonStyle(.plain)
            } else if e?.regenerar == true {
                AvisoConsola(texto: "Hay que hacer una nueva")
            }
            Button { regenerar() } label: { Text(seguro ? "¿Seguro? La vieja deja de andar" : "Regenerar") }.tecla(.negra, chica: true)
        }
    }

    private func regenerar() {
        guard seguro else {
            seguro = true
            Task { try? await Task.sleep(for: .seconds(4)); seguro = false }
            return
        }
        seguro = false
        Task {
            do { e = try await api.regenerarEntrantes() } catch { self.error = error.localizedDescription }
        }
    }

    private var servicios: some View {
        VStack(spacing: 10) {
            Bandeja {
                HStack(spacing: 12) {
                    logo("chevron.left.forwardslash.chevron.right", Color(hex: 0x24292F))
                    VStack(alignment: .leading, spacing: 6) {
                        fila("Webhooks", "Add webhook")
                        fila("Content type", "application/json")
                        HStack {
                            Grabado("Secret", color: Color.tinta.opacity(0.66))
                            Spacer()
                            Button { if let t = e?.token { copiar(t, "token") } } label: { Text(copiado == "token" ? "Copiado" : "Copiar") }
                                .tecla(chica: true).disabled((e?.token ?? "").isEmpty)
                        }
                    }
                }
            }
            Bandeja {
                HStack(spacing: 12) {
                    logo("dollarsign", Color(hex: 0x009EE3))
                    VStack(alignment: .leading, spacing: 6) {
                        fila("Mercado Pago", "Webhooks · Pagos")
                        if e?.mercadoPago == true {
                            HStack {
                                Led(estado: .verde)
                                Grabado("Con monto", color: Color.tinta.opacity(0.66))
                                Spacer()
                                Button { Task { try? await api.sacarMercadoPago(); await cargar() } } label: { Text("Sacar") }.tecla(.negra, chica: true)
                            }
                        } else {
                            HStack(spacing: 6) {
                                SecureField("", text: $mp, prompt: Text("Access token").foregroundColor(Color(hex: 0x5A524A)))
                                    .font(Tipos.marca(13, .bold)).foregroundStyle(Color.papel)
                                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
                                Button { guardarMP() } label: { Text("Guardar") }.tecla(chica: true).disabled(mp.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
            }
        }
    }

    private func logo(_ s: String, _ c: Color) -> some View {
        Image(systemName: s).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.papel)
            .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 15).fill(c))
    }

    private func fila(_ a: String, _ b: String) -> some View {
        HStack {
            Grabado(a, color: Color.tinta.opacity(0.66))
            Spacer()
            Text(b).font(Tipos.marca(12, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func guardarMP() {
        let t = mp.trimmingCharacters(in: .whitespaces)
        Task {
            do { try await api.guardarMercadoPago(t); mp = ""; await cargar() } catch { self.error = error.localizedDescription }
        }
    }

    private func tipo(_ t: String) -> some View {
        let x = ENTRANTES[t]
        return Visor(relleno: 10) {
            HStack {
                Image(systemName: x?.icono ?? "bell.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.brasa)
                Spacer()
                Text((x?.nombre ?? t).uppercased()).font(Tipos.marca(12, .black)).foregroundStyle(Color.papel)
            }
            ZStack {
                Color.black
                if let c = x?.cara {
                    MiniCara(nombre: c, config: nil, pantalla: Pantalla(), ancho: 100)
                } else {
                    Text(x?.titulo ?? "").font(Tipos.marca(11, .black)).foregroundStyle(Color.tinta)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.papel))
                }
            }
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Button { probar(t) } label: { Text(probado[t] ?? "Probar") }.tecla(chica: true, ancha: true).disabled((e?.token ?? "").isEmpty)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ultimo == t ? Color.brasa : Color.clear, lineWidth: 2))
    }

    private func probar(_ t: String) {
        guard let token = e?.token, !token.isEmpty, let x = ENTRANTES[t] else { return }
        probado[t] = "…"
        Task {
            do {
                let n = try await api.probarEntrante(token: token, tipo: t, titulo: x.titulo, de: x.de, robot: modelo.id)
                probado[t] = n > 0 ? "¡Llegó!" : "Desconectado"
            } catch {
                probado[t] = "No pude"
            }
            try? await Task.sleep(for: .seconds(2.5))
            probado[t] = nil
        }
    }
}
