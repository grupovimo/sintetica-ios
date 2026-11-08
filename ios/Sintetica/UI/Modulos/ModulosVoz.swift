import AVFoundation
import SwiftUI

// La voz de la nube (web/src/lib/consola/modulos): leer en voz alta con la
// gratis o con ElevenLabs, el paquete sin internet y la IA propia de la charla.

/// Una prueba sonando a la vez.
@MainActor
enum Parlante {
    private static var sonando: AVAudioPlayer?
    static func tocar(_ mp3: Data) throws {
        sonando?.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        let p = try AVAudioPlayer(data: mp3)
        sonando = p
        p.play()
    }
}

/// Un medidor de lo usado hoy contra el tope (0 = sin tope).
struct Medidor: View {
    let nombre: String
    let valor: Int
    let de: Int
    var mostrar: (Int) -> String = { String($0) }

    var body: some View {
        let f: Double = de > 0 ? min(1, Double(valor) / Double(de)) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Grabado(nombre, color: Color.tinta.opacity(0.66))
                Spacer()
                Text(de > 0 ? "\(mostrar(valor)) / \(mostrar(de))" : mostrar(valor)).font(Tipos.marca(11, .black).monospacedDigit()).foregroundStyle(Color.tinta)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hundido)
                    Capsule().fill(f > 0.9 ? Color.rojo : Color.led).frame(width: g.size.width * f)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nombre): \(valor)\(de > 0 ? " de \(de)" : "")")
    }
}

/// Leer en voz alta: la voz gratis (Edge) o la de tu cuenta de ElevenLabs
/// (tu clave, tus topes). La llave prende o apaga la lectura.
@MainActor
struct LeerVoz: View {
    let modelo: ModeloRobot
    @Environment(\.openURL) private var abrir
    @State private var edge: VozEdge?
    @State private var eleven: VozEleven?
    @State private var pestana = "edge"
    @State private var clave = ""
    @State private var ocupado = ""
    @State private var error = ""
    @State private var reloj: Task<Void, Never>?
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }
    private var leyendoEleven: Bool { eleven?.conectado == true && eleven?.leer == true }
    private var leyendo: Bool { leyendoEleven || (edge?.disponible == true && edge?.prendida == true) }

    var body: some View {
        if modelo.esNube {
            Bandeja {
                HStack(spacing: 8) {
                    Llave(texto: "Leer en voz alta", prendida: leyendo) { Task { await llave() } }
                    Spacer(minLength: 0)
                    if edge?.disponible == true {
                        Button { Task { await elegir("edge") } } label: { Text("Gratis") }.tecla(chica: true, hundida: pestana == "edge")
                    }
                    Button { Task { await elegir("eleven") } } label: { Text("ElevenLabs") }.tecla(chica: true, hundida: pestana == "eleven")
                }
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                if pestana == "edge", let e = edge, e.disponible {
                    gratis(e)
                } else if let x = eleven, !x.conectado {
                    conectar
                } else if let x = eleven {
                    cuenta(x)
                }
            }
            .task { await cargar(primera: true) }
            .onAppear { oyente = EnVivo.compartido.escuchar { e in if e.tipo == "voz" { Task { await cargar() } } } }
            .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
        }
    }

    private func cargar(primera: Bool = false) async {
        async let e = try? api.vozEdge()
        async let x = try? api.vozEleven()
        let (ve, vx) = await (e, x)
        edge = ve
        eleven = vx
        if primera {
            let usaEleven = vx?.conectado == true && (vx?.leer == true || ve?.disponible != true)
            pestana = usaEleven ? "eleven" : ve?.disponible == true ? "edge" : "eleven"
        }
    }

    private func ponerEdge(_ c: [String: Any]) async {
        error = ""
        do { edge = try await api.ponerVozEdge(c) } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    private func ponerEleven(_ c: [String: Any]) async -> Bool {
        error = ""
        do { eleven = try await api.ponerVozEleven(c); return true } catch { self.error = error.localizedDescription; return false }
    }

    private func elegir(_ p: String) async {
        pestana = p
        if p == "edge", leyendoEleven {
            await ponerEleven(["leer": false])
            if edge?.disponible == true, edge?.prendida != true { await ponerEdge(["prendida": true]) }
        }
        if p == "eleven", eleven?.conectado == true, eleven?.leer != true { await ponerEleven(["leer": true]) }
    }

    private func llave() async {
        if leyendo {
            if leyendoEleven { await ponerEleven(["leer": false]) }
            if edge?.prendida == true { await ponerEdge(["prendida": false]) }
        } else if pestana == "eleven", eleven?.conectado == true {
            await ponerEleven(["leer": true])
        } else if edge?.disponible == true {
            await ponerEdge(["prendida": true])
        }
    }

    private func probar(_ cual: String) {
        error = ""
        ocupado = "probar"
        let t = "¡Hola! Soy \(modelo.nombre)."
        Task {
            do { try Parlante.tocar(try await api.probarVoz(cual, texto: t)) } catch { self.error = error.localizedDescription }
            ocupado = ""
        }
    }

    private func gratis(_ e: VozEdge) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(e.voces) { v in Button(nombreVozEdge(v)) { Task { await ponerEdge(["voz": v.id]) } } }
                } label: { selector("Voz", e.voces.first { $0.id == e.voz }.map(nombreVozEdge) ?? e.voz) }
                Button { probar("edge") } label: { Label(ocupado == "probar" ? "…" : "Probar", systemImage: "play.fill") }.tecla(.naranja, chica: true)
                    .disabled(ocupado == "probar")
            }
            Medidor(nombre: "Letras hoy", valor: e.usadosHoy, de: e.tope, mostrar: miles)
        }
    }

    private var conectar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Visor(relleno: 12) {
                Grabado("Clave de ElevenLabs")
                HStack(spacing: 8) {
                    SecureField("", text: $clave, prompt: Text("sk_…").foregroundColor(Color(hex: 0x5A524A)))
                        .font(Tipos.marca(15, .bold)).foregroundStyle(Color.papel)
                    Button {
                        let c = clave.trimmingCharacters(in: .whitespaces)
                        ocupado = "conectar"
                        Task {
                            if await ponerEleven(["clave": c]) { clave = "" }
                            ocupado = ""
                        }
                    } label: { Text(ocupado == "conectar" ? "…" : "Conectar") }.tecla(.naranja, chica: true)
                        .disabled(clave.trimmingCharacters(in: .whitespaces).isEmpty || ocupado == "conectar")
                }
            }
            Button { if let u = URL(string: "https://elevenlabs.io/app/settings/api-keys") { abrir(u) } } label: {
                Label("Sacar una clave", systemImage: "arrow.up.right.square")
            }
            .tecla(.negra, chica: true)
        }
    }

    private func cuenta(_ x: VozEleven) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(x.voces) { v in Button(v.nombre) { Task { await ponerEleven(["voz": v.id]) } } }
                } label: { selector("Voz de tu cuenta", x.vozNombre.isEmpty ? x.voz : x.vozNombre) }
                Button { probar("elevenlabs") } label: { Label(ocupado == "probar" ? "…" : "Probar", systemImage: "play.fill") }.tecla(.naranja, chica: true)
                    .disabled(ocupado == "probar")
            }
            HStack(spacing: 16) {
                Perilla(nombre: "Letras/día", valor: Double(escalon(ESCALONES_LETRAS, x.tope)), min: 0, max: Double(ESCALONES_LETRAS.count - 1), paso: 1,
                        mostrar: { miles(ESCALONES_LETRAS[Int($0)]) }, tamano: 54) { i in tope("tope", ESCALONES_LETRAS[Int(i)]) }
                Perilla(nombre: "Min/día", valor: Double(escalon(ESCALONES_MINUTOS, x.topeMinutos)), min: 0, max: Double(ESCALONES_MINUTOS.count - 1), paso: 1,
                        mostrar: { ESCALONES_MINUTOS[Int($0)] == 0 ? "Off" : String(ESCALONES_MINUTOS[Int($0)]) }, tamano: 54) { i in
                    tope("tope_minutos", ESCALONES_MINUTOS[Int(i)])
                }
            }
            .frame(maxWidth: .infinity)
            Medidor(nombre: "Letras hoy", valor: x.usadosHoy, de: x.tope, mostrar: miles)
            Medidor(nombre: "Min hoy", valor: x.segundosHoy / 60, de: x.topeMinutos)
            HStack {
                Spacer()
                Button {
                    ocupado = "desconectar"
                    Task {
                        do { eleven = try await api.sacarVozEleven() } catch { self.error = error.localizedDescription }
                        ocupado = ""
                    }
                } label: { Text("Desconectar") }.tecla(.negra, chica: true).disabled(ocupado == "desconectar")
            }
        }
    }

    /// Los topes se mandan al rato de dejar de girar.
    private func tope(_ k: String, _ v: Int) {
        if k == "tope" { eleven?.tope = v } else { eleven?.topeMinutos = v }
        reloj?.cancel()
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            await ponerEleven([k: v])
        }
    }

    private func selector(_ rotulo: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Grabado(rotulo)
            HStack {
                Text(t).font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.gris)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.hundido))
    }
}

/// El paquete de voz sin internet: las frases que dice solo, ya grabadas con su
/// voz. Con ElevenLabs gasta de tu cuenta: antes se muestra cuánto y se confirma.
@MainActor
struct PaqueteVozVista: View {
    let modelo: ModeloRobot
    @State private var p: PaqueteVoz?
    @State private var confirmar: PaqueteVoz?
    @State private var error = ""
    @State private var pidiendo = false
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        Group {
            if let p, p.disponible { contenido(p) }
        }
        .task {
            guard modelo.esNube else { return }
            await cargar()
            // Mientras se graba, se mira cada tanto (y al terminar llega el evento).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if p?.estado == "generando" { await cargar() }
            }
        }
        .onAppear {
            oyente = EnVivo.compartido.escuchar { e in
                if (e.tipo == "voz-paquete" && e.bicho == modelo.id) || e.tipo == "voz" { Task { await cargar() } }
            }
        }
        .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
    }

    private func cargar() async { p = try? await api.paqueteVoz(modelo.id) }

    private func led(_ e: String) -> EstadoLed {
        switch e {
        case "listo": .verde
        case "parcial", "generando": .ambar
        case "error": .rojo
        default: .apagado
        }
    }

    private func contenido(_ p: PaqueteVoz) -> some View {
        Bandeja {
            HStack(spacing: 8) {
                Led(estado: led(p.estado))
                Image(systemName: "wifi.slash").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.tinta).accessibilityLabel("Sin internet")
                Grabado(p.etiqueta, color: Color.tinta.opacity(0.7))
                Spacer()
                Grabado(p.proveedor == "elevenlabs" ? "ElevenLabs" : "Gratis", color: Color.tinta.opacity(0.66))
            }
            HStack(spacing: 8) {
                dato("Versión", p.hay ? "v\(p.version)" : "—")
                dato("Frases", "\(p.frases)/\(p.total)")
                dato("MB", megas(p.hay ? p.bytes : p.bytesEstimados) + (p.hay ? "" : "≈"))
            }
            if p.estado == "generando", p.de > 0 { ProgressView(value: Double(p.hechas), total: Double(p.de)).tint(Color.tinta) }
            if !p.error.isEmpty { AvisoConsola(texto: p.error, error: true) }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            if let c = confirmar {
                Visor(relleno: 12) {
                    Grabado("Gasta de tu cuenta")
                    Digitos(texto: "\(miles(c.gasta)) letras", chicos: true)
                    HStack(spacing: 8) {
                        Button { generar(si: true) } label: { Text("Generar") }.tecla(.naranja, chica: true).disabled(pidiendo)
                        Button { confirmar = nil } label: { Text("Cancelar") }.tecla(.negra, chica: true)
                    }
                }
            } else if p.estado != "generando" {
                Button { generar(si: false) } label: {
                    Label(p.hay ? (p.cambio ? "Actualizar" : "Rehacer") : "Grabar", systemImage: "waveform.badge.plus")
                }
                .tecla(.negra, chica: true).disabled(pidiendo)
            }
        }
    }

    private func dato(_ t: String, _ v: String) -> some View {
        Visor(relleno: 10) {
            Grabado(t)
            Digitos(texto: v, chicos: true)
        }
    }

    private func generar(si: Bool) {
        error = ""
        pidiendo = true
        Task {
            do {
                let r = try await api.generarPaqueteVoz(modelo.id, confirmar: si)
                if r.confirmar { confirmar = r.paquete } else { p = r.paquete; confirmar = nil }
            } catch {
                self.error = error.localizedDescription
            }
            pidiendo = false
        }
    }
}

/// La IA de la charla: la del servidor, la tuya (tu clave, tu tope y tu
/// factura) o ninguna (charla su motor propio). Tres LEDs dicen cuál usa.
@MainActor
struct IAPropiaVista: View {
    @Environment(\.openURL) private var abrir
    @State private var ia: IAPropia?
    @State private var servicio = "groq"
    @State private var url = SERVICIOS_IA[1].url
    @State private var modeloIA = SERVICIOS_IA[1].modelo
    @State private var clave = ""
    @State private var abierto = false
    @State private var ocupado = false
    @State private var error = ""
    @State private var reloj: Task<Void, Never>?
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }
    private var s: ServicioIA { SERVICIOS_IA.first { $0.clave == servicio } ?? SERVICIOS_IA[0] }

    var body: some View {
        Group {
            if let ia { contenido(ia) }
        }
        .task { ia = try? await api.iaPropia() }
        .onAppear { oyente = EnVivo.compartido.escuchar { e in if e.tipo == "ia" { Task { ia = try? await api.iaPropia() } } } }
        .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
    }

    private func contenido(_ ia: IAPropia) -> some View {
        Bandeja {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.brasa)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(hex: 0x3A3632), Color(hex: 0x1D1B18)], startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 6) {
                    Grabado("Charla · con qué IA", color: Color.tinta.opacity(0.66))
                    HStack(spacing: 10) {
                        cual("Servidor", ia.cual == "servidor", .verde)
                        cual("Tuya", ia.cual == "tuya", .verde)
                        cual("Ninguna", ia.cual == "ninguna", .ambar)
                    }
                }
                Spacer(minLength: 0)
            }
            if !ia.propia, !abierto {
                Button { abierto = true } label: { Label("Tu clave", systemImage: "plus") }.tecla(.naranja, chica: true)
            }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            if ia.propia {
                propia(ia)
            } else if abierto {
                forma
            } else if ia.servidor {
                Medidor(nombre: "Hoy", valor: ia.usadasHoy, de: ia.tope)
            }
        }
    }

    private func cual(_ t: String, _ si: Bool, _ led: EstadoLed) -> some View {
        HStack(spacing: 5) {
            Led(estado: si ? led : .apagado, tamano: 7)
            Text(t.uppercased()).font(Tipos.marca(9.5, .heavy)).foregroundStyle(si ? Color.tinta : Color.tinta.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(si ? [.isSelected] : [])
    }

    private func propia(_ ia: IAPropia) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Visor(relleno: 10) {
                    Grabado("Servicio")
                    Text(servicioDe(ia)).font(Tipos.marca(14, .black)).foregroundStyle(Color.papel).lineLimit(1)
                }
                CampoModelo(valor: ia.modelo) { m in Task { await cambiar(["modelo": m]) } }
            }
            HStack(spacing: 14) {
                Perilla(nombre: "Tope/día", valor: Double(escalon(ESCALONES_IA, ia.tope)), min: 0, max: Double(ESCALONES_IA.count - 1), paso: 1,
                        mostrar: { ESCALONES_IA[Int($0)] == 0 ? "∞" : String(ESCALONES_IA[Int($0)]) }, tamano: 52) { i in tope(ESCALONES_IA[Int(i)]) }
                VStack(spacing: 10) {
                    Medidor(nombre: "Hoy", valor: ia.usadasHoy, de: ia.tope)
                    Button { Task { try? await api.borrarIA(); self.ia = try? await api.iaPropia() } } label: { Text("Borrar") }.tecla(.negra, chica: true)
                }
            }
        }
    }

    private var forma: some View {
        VStack(alignment: .leading, spacing: 10) {
            Flujo(espacio: 6, renglon: 4) {
                ForEach(SERVICIOS_IA, id: \.clave) { x in
                    Button { elegir(x) } label: { Text(x.nombre) }.tecla(chica: true, hundida: servicio == x.clave)
                }
            }
            if s.proveedor == "compatible" {
                CampoVisor(rotulo: "URL", texto: $url, ayuda: "https://…/v1", claro: true, teclado: .URL)
            }
            CampoVisor(rotulo: "Modelo", texto: $modeloIA, ayuda: "modelo", claro: true, teclado: .asciiCapable)
            Visor(relleno: 12) {
                Grabado("Clave")
                SecureField("", text: $clave).font(Tipos.marca(15, .bold)).foregroundStyle(Color.papel)
            }
            HStack(spacing: 8) {
                Button { Task { await conectar() } } label: { Text(ocupado ? "…" : "Conectar") }.tecla(.naranja, chica: true)
                    .disabled(ocupado || clave.trimmingCharacters(in: .whitespaces).isEmpty
                        || (s.proveedor == "compatible" && (url.trimmingCharacters(in: .whitespaces).isEmpty || modeloIA.trimmingCharacters(in: .whitespaces).isEmpty)))
                Button { abierto = false } label: { Text("Cancelar") }.tecla(.negra, chica: true)
                Spacer(minLength: 0)
                if !s.claves.isEmpty, let u = URL(string: s.claves) {
                    Button { abrir(u) } label: { Image(systemName: "key.fill") }.tecla(.negra, cuadrada: true).accessibilityLabel("Sacar una clave")
                }
            }
        }
    }

    private func elegir(_ x: ServicioIA) {
        servicio = x.clave
        url = x.url
        modeloIA = x.modelo
    }

    private func conectar() async {
        error = ""
        ocupado = true
        var c: [String: Any] = ["proveedor": s.proveedor, "clave": clave.trimmingCharacters(in: .whitespaces)]
        let m = modeloIA.trimmingCharacters(in: .whitespaces)
        if !m.isEmpty { c["modelo"] = m }
        if s.proveedor == "compatible" { c["url"] = url.trimmingCharacters(in: .whitespaces) }
        do {
            ia = try await api.ponerIA(c)
            clave = ""
            abierto = false
        } catch {
            self.error = error.localizedDescription
        }
        ocupado = false
    }

    private func cambiar(_ c: [String: Any]) async {
        error = ""
        do { ia = try await api.ponerIA(c) } catch { self.error = error.localizedDescription; ia = try? await api.iaPropia() }
    }

    private func tope(_ v: Int) {
        ia?.tope = v
        reloj?.cancel()
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            await cambiar(["tope": v])
        }
    }
}

/// El modelo de la IA propia (se guarda al terminar de escribir).
private struct CampoModelo: View {
    let valor: String
    let alGuardar: (String) -> Void
    @State private var texto = ""
    var body: some View {
        CampoVisor(rotulo: "Modelo", texto: $texto, ayuda: "modelo", claro: true, teclado: .asciiCapable) {
            let m = texto.trimmingCharacters(in: .whitespaces)
            if !m.isEmpty, m != valor { alGuardar(m) }
        }
        .onAppear { texto = valor }
    }
}
