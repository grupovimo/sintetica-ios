import SwiftUI
import UIKit

private let CARAS_AUTO = ["contento", "sorpresa", "enamorado", "guino", "triste", "pensando", "dormido"]

/// Integraciones: el robot conectado al mundo desde la nube. Tu IA (MCP),
/// Telegram (le escribís y te avisa), webhooks y automatizaciones: cuando
/// pasa algo, hace cosas. Como web/src/lib/consola/modulos/Integraciones.svelte.
@MainActor
struct ModIntegraciones: View {
    let modelo: ModeloRobot
    @Environment(\.openURL) private var abrirURL
    @State private var telegram: EstadoTelegram?
    @State private var autos: [Automatizacion] = []
    @State private var historial: [Ejecucion] = []
    @State private var cuandos = ["recordatorio", "bateria-baja", "desconectado", "conectado", "despierta", "duerme", "expresion"]
    @State private var otros: [RobotNube] = []
    @State private var clientes: [ClienteMCP] = []
    @State private var urlMCP = ""
    @State private var copiado = false
    @State private var tokens: [TokenIA] = []
    @State private var tokenNuevo = ""
    @State private var urlToken = ""
    @State private var comandoCopiado = false
    @State private var secreto = ""
    @State private var error = ""
    @State private var sinNube = false
    @State private var guardando = ""
    @State private var probado: [String: String] = [:]
    @State private var reloj: Task<Void, Never>?
    @State private var oyente: UUID?
    @State private var esperando: Task<Void, Never>?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        if !modelo.esNube {
            Bandeja {
                HStack(spacing: 16) {
                    Image(systemName: "icloud.slash.fill").font(.system(size: 30, weight: .bold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOLO CON LA NUBE").font(Tipos.marca(18, .black))
                        Text("Sumalo a tu cuenta.").font(Tipos.texto).opacity(0.75)
                    }
                }
                .foregroundStyle(Color.tinta)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                if sinNube {
                    AvisoConsola(texto: "Todavía no en esta nube.")
                } else {
                    tuIA
                    bloqueTelegram
                    HStack {
                        Grabado("Automatizaciones\(guardando)", color: Color.tinta.opacity(0.66))
                        Spacer()
                        Button { autos.append(Automatizacion.nueva()); guardar() } label: { Label("Nueva", systemImage: "plus") }
                            .tecla(.negra).disabled(autos.count >= 20)
                    }
                    if autos.isEmpty {
                        Bandeja { Text("Ej.: recordatorio → Telegram").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8)) }
                    }
                    ForEach(autos.indices, id: \.self) { i in fichaAuto(i) }
                    Text(PLANTILLAS_AUTO.joined(separator: " ")).font(Tipos.marca(10.5, .bold)).foregroundStyle(Color.tinta.opacity(0.7))
                    desarrolladores
                    if !historial.isEmpty { ultimas }
                }
            }
            .task { await cargar() }
            .onAppear {
                oyente = EnVivo.compartido.escuchar { e in
                    if e.tipo == "telegram" || e.tipo == "mcp" || (e.tipo == "automatizacion" && e.bicho == modelo.id) { Task { await cargar() } }
                }
            }
            .onDisappear {
                if let o = oyente { EnVivo.compartido.dejar(o) }
                esperando?.cancel()
            }
        }
    }

    private func texto(_ e: Error) -> String { e.localizedDescription }

    private func cargar() async {
        do {
            telegram = try await api.telegram()
            let r = try await api.automatizaciones(modelo.id)
            autos = r.lista
            historial = r.historial
            if !r.cuandos.isEmpty { cuandos = r.cuandos }
            sinNube = false
        } catch let e as ErrorApi where e.estado == 404 {
            sinNube = true
        } catch {
            self.error = texto(error)
        }
        if let l = try? await api.robots() { otros = l.filter { $0.id != modelo.id } }
        if let m = try? await api.clientesMCP() { clientes = m.clientes; urlMCP = m.url }
        if let t = try? await api.tokensIA() { tokens = t }
    }

    // MARK: Tu IA (MCP)

    private var tuIA: some View {
        Bandeja {
            HStack(spacing: 14) {
                Text("✦").font(.system(size: 28, weight: .black)).foregroundStyle(Color.papel)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(hex: 0x3A3632), Color(hex: 0x1D1B18)], startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 4) {
                    Grabado("Tu IA · Claude o ChatGPT", color: Color.tinta.opacity(0.66))
                    Text(clientes.isEmpty ? "QUE LA MANEJE TU IA" : "\(clientes.count) CONECTADA\(clientes.count > 1 ? "S" : "")")
                        .font(Tipos.marca(17, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            if !urlMCP.isEmpty {
                Button {
                    UIPasteboard.general.string = urlMCP
                    copiado = true
                    Task { try? await Task.sleep(for: .seconds(1.8)); copiado = false }
                } label: {
                    HStack {
                        Text(urlMCP).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.brasa).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Grabado(copiado ? "Copiada" : "Copiar")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: copiado)
                Text("Agregala como conector.").font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8))
            }
            HStack {
                Spacer()
                Button { crearToken() } label: { Label("Token", systemImage: "plus") }.tecla(.negra, chica: true)
                    .accessibilityHint("Para Claude Code")
            }
            if !tokenNuevo.isEmpty { tokenUnaVez }
            ForEach(tokens) { t in
                HStack(spacing: 10) {
                    Led(estado: .on)
                    Text(t.nombre).font(Tipos.marca(13, .bold)).foregroundStyle(Color.papel).lineLimit(1)
                    Text(t.usado.map { "usó \(hace($0))" } ?? "sin usar").font(Tipos.chico).foregroundStyle(Color.gris).lineLimit(1)
                    Spacer()
                    Button { Task { try? await api.borrarTokenIA(t.id); await cargar() } } label: { Image(systemName: "trash") }
                        .tecla(.negra, cuadrada: true).accessibilityLabel("Borrar el token")
                }
                .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
            }
            ForEach(clientes) { c in
                HStack(spacing: 10) {
                    Led(estado: .verde)
                    Text(c.cliente).font(Tipos.marca(13, .bold)).foregroundStyle(Color.papel).lineLimit(1)
                    Text(c.usada.map { "usó \(hace($0))" } ?? "sin usar").font(Tipos.chico).foregroundStyle(Color.gris).lineLimit(1)
                    Spacer()
                    Button {
                        Task { try? await api.desconectarMCP(c.id); await cargar() }
                    } label: { Text("Desconectar") }.tecla(.negra, chica: true)
                }
                .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
            }
        }
    }

    /// El token nuevo se ve una sola vez: el comando entero, para copiar.
    private var tokenUnaVez: some View {
        let cmd = comandoClaude(url: urlToken.isEmpty ? urlMCP : urlToken, token: tokenNuevo)
        return VStack(alignment: .leading, spacing: 8) {
            Grabado("Se ve una sola vez", color: Color.tinta.opacity(0.66))
            Button {
                UIPasteboard.general.string = cmd
                comandoCopiado = true
                Task { try? await Task.sleep(for: .seconds(1.8)); comandoCopiado = false }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(cmd).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.brasa)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Grabado(comandoCopiado ? "Copiado" : "Copiar")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: comandoCopiado)
        }
    }

    private func crearToken() {
        Task {
            do {
                let r = try await api.crearTokenIA()
                tokenNuevo = r.token
                urlToken = r.url
                if let t = try? await api.tokensIA() { tokens = t }
            } catch {
                self.error = texto(error)
            }
        }
    }

    // MARK: Telegram

    private var bloqueTelegram: some View {
        Bandeja {
            HStack(spacing: 14) {
                Image(systemName: "paperplane.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.papel)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(hex: 0x3AA4E0), Color(hex: 0x1D7FBF)], startPoint: .top, endPoint: .bottom)))
                    .background(RoundedRectangle(cornerRadius: 15).fill(Color(hex: 0x145A87)).offset(y: 4))
                VStack(alignment: .leading, spacing: 4) {
                    Grabado("Telegram" + ((telegram?.bot ?? "").isEmpty ? "" : " · @\(telegram?.bot ?? "")"), color: Color.tinta.opacity(0.66))
                    Text(estadoTelegram).font(Tipos.marca(17, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            if let t = telegram, t.activo {
                if t.vinculado {
                    Text("/robots  /estado  /cara").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.tinta.opacity(0.8))
                    Button { Task { try? await api.desvincularTelegram(); await cargar() } } label: { Text("Desvincular") }.tecla(.negra, chica: true)
                } else {
                    Button { vincular() } label: { Label("Vincular", systemImage: "arrow.up.forward.app") }.tecla(.naranja, ancha: true)
                }
            }
        }
    }

    private var estadoTelegram: String {
        guard let t = telegram else { return "BUSCANDO…" }
        if !t.activo { return "APAGADO EN ESTA NUBE" }
        if t.vinculado { return t.nombre.isEmpty ? "VINCULADO" : "CON \(t.nombre.uppercased())" }
        return "QUE TE HABLE"
    }

    /// Abre el link del bot directo en el celu y se fija cada tanto si ya quedó.
    private func vincular() {
        error = ""
        Task {
            do {
                guard let e = try await api.vincularTelegram(), let url = URL(string: e) else { return }
                abrirURL(url)
                esperando?.cancel()
                esperando = Task {
                    for _ in 0 ..< 300 {
                        try? await Task.sleep(for: .seconds(3))
                        if Task.isCancelled { return }
                        if let t = try? await api.telegram() { telegram = t; if t.vinculado { return } }
                    }
                }
            } catch {
                self.error = texto(error)
            }
        }
    }

    // MARK: Automatizaciones

    private func guardar() {
        guardando = " · guardando…"
        reloj?.cancel()
        let id = modelo.id
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            do {
                let r = try await api.guardarAutomatizaciones(id, autos)
                historial = r.historial
                guardando = " · guardadas"
                error = ""
            } catch {
                guardando = ""
                self.error = texto(error)
            }
        }
    }

    private func nombreRobot(_ id: String) -> String {
        if id == modelo.id { return modelo.nombre }
        guard let o = otros.first(where: { $0.id == id }) else { return id }
        return o.apodo.isEmpty ? (o.estado?.nombre ?? o.id) : o.apodo
    }

    private func fichaAuto(_ i: Int) -> some View {
        let a = autos[i]
        return Bandeja {
            HStack {
                Grabado("Cuando \(modelo.nombre)…", color: Color.tinta.opacity(0.66))
                Spacer()
                Llave(texto: a.activa ? "Activa" : "Apagada", prendida: a.activa) { autos[i].activa.toggle(); guardar() }
            }
            Menu {
                ForEach(Automatizacion.cuandos(cuandos), id: \.self) { k in
                    Button(NOMBRES_CUANDO[k] ?? k) {
                        autos[i].ponerCuando(k)
                        guardar()
                    }
                }
            } label: { selector(NOMBRES_CUANDO[a.cuando] ?? a.cuando) }
            if a.cuando == "hora" { aUnaHora(i, a) }
            if a.cuando == "expresion" {
                Menu {
                    Button("a cualquiera") { autos[i].valor = nil; guardar() }
                    ForEach(CARAS_AUTO, id: \.self) { c in Button("a \(c)") { autos[i].valor = c; guardar() } }
                } label: { selector(a.valor.map { "a \($0)" } ?? "a cualquiera") }
            }
            ForEach(a.hacer.indices, id: \.self) { j in accion(i, j) }
            Flujo(espacio: 8, renglon: 4) {
                ForEach(ACCIONES_AUTO, id: \.tipo) { t, n, icono in
                    Button { autos[i].hacer.append(AccionAuto.nueva(t, otro: otros.first?.id)); guardar() } label: { Label(n, systemImage: icono) }
                        .tecla(chica: true)
                        .disabled(a.hacer.count >= 4 || (t == "robot" && otros.isEmpty))
                }
            }
            HStack(spacing: 8) {
                Button { probar(i, a.id) } label: { Text(probado[a.id] ?? "Probar") }.tecla(chica: true)
                Spacer()
                Button { autos.remove(at: i); guardar() } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Borrar")
            }
        }
        .opacity(a.activa ? 1 : 0.6)
    }

    /// "A una hora": la hora y los días.
    private func aUnaHora(_ i: Int, _ a: Automatizacion) -> some View {
        let hora = Binding<Date>(get: {
            let m = aMinutos(a.hora ?? "08:00")
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            autos[i].hora = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            guardar()
        })
        let dias = a.dias ?? "LMXJVSD"
        return VStack(alignment: .leading, spacing: 8) {
            DatePicker("", selection: hora, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.compact).tint(Color.brasa).colorScheme(.dark)
            HStack(spacing: 5) {
                ForEach(DIAS_SEMANA, id: \.letra) { d in
                    Button { autos[i].alternarDia(d.letra); guardar() } label: { Text(d.letra) }
                        .buttonStyle(EstiloDia(prendido: dias.contains(d.letra)))
                        .accessibilityLabel(d.nombre)
                }
            }
        }
    }

    private func nombreModo(_ m: String?) -> String {
        for (k, t) in MODOS_ACCION where k == m { return t }
        return "Reloj"
    }

    private func selector(_ t: String) -> some View {
        HStack {
            Text(t).font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.gris)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
    }

    @ViewBuilder private func accion(_ i: Int, _ j: Int) -> some View {
        let h = autos[i].hacer[j]
        HStack(spacing: 8) {
            Image(systemName: "arrow.right").font(.system(size: 14, weight: .black)).foregroundStyle(Color.tinta.opacity(0.6))
            switch h.tipo {
            case "telegram":
                CampoAccion(rotulo: "Telegram", valor: h.texto ?? "", ayuda: "{robot}: {texto}") { v in autos[i].hacer[j].texto = v; guardar() }
            case "webhook":
                CampoAccion(rotulo: "POST firmado", valor: h.url ?? "", ayuda: "https://tu-api.com/gancho", url: true) { v in
                    autos[i].hacer[j].url = v.trimmingCharacters(in: .whitespaces); guardar()
                }
            case "decir":
                VStack(spacing: 6) {
                    CampoAccion(rotulo: "Dice", valor: h.texto ?? "", ayuda: "¡Hola!") { v in
                        let t = cortarBytes(v.trimmingCharacters(in: .whitespaces), MAX_TEXTO)
                        autos[i].hacer[j].texto = t.isEmpty ? "¡Hola!" : t
                        guardar()
                    }
                    Menu {
                        Button("su cara") { autos[i].hacer[j].expresion = nil; guardar() }
                        ForEach(CARAS_AUTO, id: \.self) { c in Button(c) { autos[i].hacer[j].expresion = c; guardar() } }
                    } label: { selector(h.expresion ?? "su cara") }
                }
            case "cara":
                Menu {
                    ForEach(CARAS_AUTO, id: \.self) { c in Button(c) { autos[i].hacer[j].expresion = c; guardar() } }
                } label: { selector("Cara · " + (h.expresion ?? "contento")) }
            case "modo":
                Menu {
                    ForEach(MODOS_ACCION, id: \.0) { k, t in Button(t) { autos[i].hacer[j].modo = k; guardar() } }
                } label: { selector("Pasa a · " + nombreModo(h.modo)) }
            case "despertar":
                Visor(relleno: 10) {
                    Grabado("Lo despierta")
                    Text("¡BUEN DÍA!").font(Tipos.marca(15, .black)).foregroundStyle(Color.papel)
                }
            default:
                VStack(spacing: 6) {
                    Menu {
                        ForEach(otros) { o in Button(nombreRobot(o.id)) { autos[i].hacer[j].bicho = o.id; guardar() } }
                    } label: { selector(nombreRobot(h.bicho ?? "")) }
                    Menu {
                        ForEach(CARAS_AUTO, id: \.self) { c in Button(c) { autos[i].hacer[j].expresion = c; guardar() } }
                    } label: { selector(h.expresion ?? "contento") }
                }
            }
            Button { autos[i].hacer.remove(at: j); guardar() } label: { Image(systemName: "xmark") }
                .tecla(.negra, cuadrada: true).disabled(autos[i].hacer.count == 1).accessibilityLabel("Quitar")
        }
    }

    private func probar(_ i: Int, _ clave: String) {
        probado[clave] = "Probando…"
        let id = modelo.id
        Task {
            do {
                try await api.probarAutomatizacion(id, i)
                probado[clave] = "Listo"
            } catch {
                probado[clave] = "Falló"
            }
            try? await Task.sleep(for: .seconds(4))
            probado[clave] = nil
        }
    }

    // MARK: Desarrolladores y ejecuciones

    private var desarrolladores: some View {
        Bandeja {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("POST {evento, robot, datos, en}\nX-Sintetica-Firma: sha256=HMAC")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.tinta.opacity(0.8))
                    Text(secreto.isEmpty ? "••••••••••••••••" : secreto).font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.brasa).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
                    HStack {
                        Button { cargarSecreto(rotar: false) } label: { Text(secreto.isEmpty ? "Ver" : "Ocultar") }.tecla(chica: true)
                        Button { cargarSecreto(rotar: true) } label: { Text("Rotar") }.tecla(.negra, chica: true)
                    }
                }
                .padding(.top, 10)
            } label: { Grabado("Webhooks", color: Color.tinta.opacity(0.66)) }
            .tint(Color.tinta)
        }
    }

    private func cargarSecreto(rotar: Bool) {
        if !rotar, !secreto.isEmpty { secreto = ""; return }
        Task {
            do { secreto = try await api.secretoWebhook(rotar: rotar) } catch { self.error = texto(error) }
        }
    }

    private var ultimas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grabado("Últimas", color: Color.tinta.opacity(0.66))
            ForEach(historial.prefix(6)) { h in
                HStack(spacing: 10) {
                    Led(estado: h.ok ? .verde : .on)
                    Text(h.en.map { hace($0) } ?? "").font(Tipos.chico).foregroundStyle(Color.hueso)
                    Text("\(NOMBRES_CUANDO[h.evento] ?? h.evento) → \(h.accion)").font(Tipos.chico).foregroundStyle(Color.gris).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
            }
        }
    }
}

/// Un campo de una acción (se guarda al terminar de escribir).
private struct CampoAccion: View {
    let rotulo: String
    let valor: String
    let ayuda: String
    var url = false
    let alGuardar: (String) -> Void
    @State private var texto = ""

    var body: some View {
        CampoVisor(rotulo: rotulo, texto: $texto, ayuda: ayuda, claro: true, teclado: url ? .URL : .default) {
            if texto != valor { alGuardar(texto) }
        }
        .onAppear { texto = valor }
    }
}
