import SwiftUI
import UIKit

// 19 · Tu IA y 33 · IA y gasto.

/// Un día de la semana de charlas (GET /v1/ia → semana).
struct DiaCharlas: Identifiable, Equatable {
    let dia: String
    let charlas: Int
    var id: String { dia }
}

/// El correo (Gmail y Outlook): si se puede y si está conectado.
struct EstadoCorreo: Equatable {
    var gmailDisponible = false, gmail = false, outlookDisponible = false, outlook = false
    init(_ o: [String: Any]) {
        let g = o["gmail"] as? [String: Any] ?? [:], ol = o["outlook"] as? [String: Any] ?? [:]
        gmailDisponible = g["disponible"] as? Bool ?? false
        gmail = g["conectada"] as? Bool ?? false
        outlookDisponible = ol["disponible"] as? Bool ?? false
        outlook = ol["conectada"] as? Bool ?? false
    }
}

extension ApiSintetica {
    /// La IA con la semana de charlas (del más viejo a hoy).
    func iaConSemana() async throws -> (ia: IAPropia, semana: [DiaCharlas]) {
        let o = try await pedir("/v1/ia")
        let s = (o["semana"] as? [[String: Any]] ?? []).map {
            DiaCharlas(dia: $0["dia"] as? String ?? "", charlas: ($0["charlas"] as? NSNumber)?.intValue ?? 0)
        }
        return (IAPropia(o), s)
    }

    func correo() async throws -> EstadoCorreo { EstadoCorreo(try await pedir("/v1/correo")) }
    func enlaceCorreo(_ proveedor: String) async throws -> String { (try await pedir("/v1/correo/\(proveedor)"))["url"] as? String ?? "" }
}

/// 19 · Tu IA: Claude (con su logo), ChatGPT (solo texto), cómo conectarla
/// por MCP paso a paso y con qué más se conecta.
@MainActor
struct TuIAS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @Environment(\.openURL) private var abrir
    @State private var cargando = true
    @State private var fallo = false
    @State private var clientes: [ClienteMCP] = []
    @State private var urlMCP = ""
    @State private var copiado = false
    @State private var telegram: EstadoTelegram?
    @State private var entrantes: Entrantes?
    @State private var agenda: Agenda?
    @State private var eleven: VozEleven?
    @State private var musica: Musica?
    @State private var correo: EstadoCorreo?
    @State private var ocupado = ""
    @State private var error = ""

    private var api: ApiSintetica { Cuenta.compartida.api }
    private var conClaude: Bool { clientes.contains { $0.cliente.lowercased().contains("claude") } }
    private var conChatGPT: Bool { clientes.contains { let n = $0.cliente.lowercased(); return n.contains("chatgpt") || n.contains("openai") } }

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if cargando {
            EstadoCargando(renglones: 4).task { await cargar() }
        } else if fallo {
            EstadoError(texto: "No pude ver tu IA.") { Task { await cargar() } }
        } else {
            contenido
        }
    }

    @ViewBuilder private var contenido: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.bottom, 12) }
            Seccion("Tu asistente", arriba: 0)
            HStack(spacing: 12) {
                FichaLogo(imagen: "logo-claude")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                    Text("Funciona con Claude, de Anthropic").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                EstadoIntegracion(conectada: conClaude) { if let u = URL(string: "https://claude.ai/settings/connectors") { abrir(u) } }
            }
            .padding(.vertical, 12)
            Text(conChatGPT ? "También está con ChatGPT." : "También funciona con ChatGPT.").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
            Seccion("Conectala por MCP")
            VStack(alignment: .leading, spacing: 16) {
                paso(1) { Text("En Claude: Ajustes › Conectores › Agregar.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta) }
                paso(2) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pegá el enlace de \(sesion.nombre).").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                        HStack(spacing: 8) {
                            Text(urlMCP.isEmpty ? "—" : urlMCP).font(S1Tipo.mono(13)).foregroundStyle(Color.s1Tinta)
                                .lineLimit(1).truncationMode(.middle)
                                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Campo))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.s1Linea, lineWidth: 1))
                            Button {
                                UIPasteboard.general.string = urlMCP
                                copiado = true
                                Task { try? await Task.sleep(for: .seconds(1.8)); copiado = false }
                            } label: { Text(copiado ? "Copiado" : "Copiar") }
                                .tecla(chica: true).disabled(urlMCP.isEmpty)
                                .sensoryFeedback(.success, trigger: copiado)
                        }
                    }
                }
                paso(3) { Text("Pedile: «Decile a mi S1 que me recuerde el dentista».").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta) }
            }
            if !clientes.isEmpty {
                Seccion("Conectadas")
                VStack(spacing: 0) {
                    ForEach(clientes) { c in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.cliente).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                                Text(c.usada.map { "Usó \(hace($0))" } ?? "Sin usar").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                            }
                            Spacer()
                            Button { Task { try? await api.desconectarMCP(c.id); await cargar() } } label: { Text("Sacar") }.tecla(chica: true)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                    }
                }
            }
            Seccion("Se conecta con")
            VStack(spacing: 0) {
                FilaIntegracion(logo: "logo-mercadopago", nombre: "Mercado Pago", detalle: "Cobros con QR", conectada: entrantes?.mercadoPago == true,
                                ocupado: ocupado == "mp") { conectarMP() }
                FilaIntegracion(logo: "logo-telegram", nombre: "Telegram", detalle: "Avisos a la familia", conectada: telegram?.vinculado == true,
                                ocupado: ocupado == "tg") { conectarTelegram() }
                FilaIntegracion(logo: "logo-googlecalendar", nombre: "Google Calendar", detalle: "Tus turnos", conectada: agenda?.conectada == true) {
                    ir(.modulo(.agenda))
                }
                FilaIntegracion(logo: "logo-elevenlabs", nombre: "ElevenLabs", detalle: "Su voz", conectada: eleven?.conectado == true) { ir(.modulo(.voz)) }
                if musica?.disponible == true {
                    FilaIntegracion(logo: "logo-spotify", nombre: "Spotify", detalle: "Tu música", conectada: musica?.conectada == true,
                                    ocupado: ocupado == "sp") { conectarSpotify() }
                }
                FilaIntegracion(logo: "logo-github", nombre: "GitHub", detalle: "Avisos de tus repos", conectada: false) { ir(.modulo(.avisos)) }
                if correo?.gmailDisponible == true {
                    FilaIntegracion(logo: "logo-mail", nombre: "Gmail", detalle: "Te lee los importantes", conectada: correo?.gmail == true,
                                    ocupado: ocupado == "gmail") { conectarCorreo("gmail") }
                }
                if correo?.outlookDisponible == true {
                    FilaIntegracion(logo: "logo-mail", nombre: "Outlook", detalle: "Te lee los importantes", conectada: correo?.outlook == true,
                                    ocupado: ocupado == "outlook") { conectarCorreo("outlook") }
                }
            }
            Seccion("Más")
            Button { ir(.modulo(.iaGasto)) } label: {
                FilaS1(titulo: "IA y gasto", detalle: "Cuánto charla y tu clave", flecha: true) { IconoEnCirculo(icono: .sistema("key")) }
            }
            .buttonStyle(.plain)
            Seccion("Avanzado")
            ModIntegraciones(modelo: sesion.modelo)
        }
    }

    private func paso<C: View>(_ n: Int, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(S1Tipo.captionFuerte).foregroundStyle(Color.s1InvTexto)
                .frame(width: 28, height: 28).background(Circle().fill(Color.s1Inv))
            c()
            Spacer(minLength: 0)
        }
    }

    private func cargar() async {
        do {
            let m = try await api.clientesMCP()
            clientes = m.clientes
            urlMCP = m.url
            fallo = false
        } catch {
            if cargando { fallo = true }
        }
        telegram = try? await api.telegram()
        entrantes = try? await api.entrantes()
        agenda = try? await api.agenda()
        eleven = try? await api.vozEleven()
        musica = try? await api.musica()
        correo = try? await api.correo()
        cargando = false
    }

    private func abrirEnlace(_ que: String, _ f: @escaping () async throws -> String) {
        ocupado = que
        error = ""
        Task {
            defer { ocupado = "" }
            do {
                if let u = URL(string: try await f()), u.scheme != nil { abrir(u) }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func conectarMP() { abrirEnlace("mp") { try await Cuenta.compartida.api.enlaceMercadoPago() } }
    private func conectarSpotify() { abrirEnlace("sp") { try await Cuenta.compartida.api.enlaceSpotify() } }
    private func conectarCorreo(_ p: String) { abrirEnlace(p) { try await Cuenta.compartida.api.enlaceCorreo(p) } }
    private func conectarTelegram() { abrirEnlace("tg") { try await Cuenta.compartida.api.vincularTelegram() ?? "" } }
}

/// 33 · IA y gasto: cuántas charlas hoy, la semana en barras (hoy en
/// naranja), el uso del día contra el tope, el modelo y tu clave.
@MainActor
struct IAGastoS1: View {
    let sesion: SesionS1
    @State private var ia: IAPropia?
    @State private var semana: [DiaCharlas] = []
    @State private var fallo = false

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if fallo && ia == nil {
            EstadoError(texto: "No pude ver el gasto.") { Task { await cargar() } }
        } else if let ia {
            contenido(ia)
        } else {
            EstadoCargando(renglones: 3).task { await cargar() }
        }
    }

    private func cargar() async {
        do {
            let r = try await Cuenta.compartida.api.iaConSemana()
            ia = r.ia
            semana = r.semana
            fallo = false
        } catch {
            fallo = true
        }
    }

    @ViewBuilder private func contenido(_ ia: IAPropia) -> some View {
        let hoy = semana.last?.charlas ?? ia.usadasHoy
        let ayer = semana.count >= 2 ? semana[semana.count - 2].charlas : 0
        VStack(alignment: .leading, spacing: 0) {
            Text("\(hoy) \(hoy == 1 ? "charla" : "charlas")").font(.system(size: 44, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.6)
            Text(comparar(hoy, ayer)).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            if semana.isEmpty {
                EstadoVacio(texto: "Todavía no charlaron.", expresion: "pensando")
            } else {
                barras.padding(.top, 24)
            }
            Seccion("Uso de hoy")
            if ia.tope > 0 {
                let f = min(1, Double(ia.usadasHoy) / Double(max(1, ia.tope)))
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.s1Superficie)
                            Capsule().fill(f >= 0.8 ? Color.s1Naranja : Color.s1Inv).frame(width: g.size.width * CGFloat(f))
                        }
                    }
                    .frame(height: 12)
                    Text("\(ia.usadasHoy) de \(ia.tope) · \(Int((f * 100).rounded()))%").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                }
            } else {
                Text("\(ia.usadasHoy) · sin tope").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
            }
            Seccion("Modelo")
            HStack(spacing: 12) {
                if ia.propia && ia.proveedor != "anthropic" {
                    IconoEnCirculo(icono: .sistema("key"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ia.modelo.isEmpty ? "Tu IA" : ia.modelo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                        Text(ia.urlPista.isEmpty ? "Con tu clave" : ia.urlPista).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1)
                    }
                } else {
                    FichaLogo(imagen: "logo-claude")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                        Text("Funciona con Claude, de Anthropic").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer()
            }
            Seccion("Tu clave")
            IAPropiaVista()
        }
        .task(id: "ia") { if semana.isEmpty { await cargar() } }
    }

    private func comparar(_ hoy: Int, _ ayer: Int) -> String {
        if semana.count < 2 { return "hoy" }
        if hoy == ayer { return "hoy · igual que ayer" }
        return hoy > ayer ? "hoy · \(hoy - ayer) más que ayer" : "hoy · \(ayer - hoy) menos que ayer"
    }

    private var barras: some View {
        let maximo = max(1, semana.map(\.charlas).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(semana.enumerated()), id: \.offset) { i, d in
                let esHoy = i == semana.count - 1
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(esHoy ? Color.s1Naranja : Color.s1Inv)
                        .frame(height: max(4, CGFloat(d.charlas) / CGFloat(maximo) * 96))
                    Text(Self.letra(d.dia)).font(esHoy ? S1Tipo.captionFuerte : S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Self.letra(d.dia)): \(d.charlas)")
            }
        }
        .frame(height: 124)
    }

    /// "2026-11-14" → la letra del día (L M M J V S D).
    static func letra(_ dia: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: dia) else { return "·" }
        let w = Calendar.current.component(.weekday, from: d)
        return ["D", "L", "M", "M", "J", "V", "S"][max(0, min(6, w - 1))]
    }
}
