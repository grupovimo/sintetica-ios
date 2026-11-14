import SwiftUI

/// La cuenta en la nube: entrar con Telegram (el botón grande abre el bot y la
/// app espera la aprobación; o el código de 6 dígitos) o con el mail, si el
/// servidor lo tiene. Como web/src/routes/entrar/+page.svelte.
@MainActor
struct CuentaVista: View {
    @Binding var ruta: [Ruta]
    @Environment(\.dismiss) private var cerrar
    @Environment(\.openURL) private var abrir
    private var cuenta = Cuenta.compartida
    @State private var servidor = Cuenta.compartida.servidor
    @State private var email = Cuenta.compartida.email
    @State private var codigo = ""
    @State private var paso = "inicio"  // inicio, telegram, mail, mailEnviado
    @State private var metodos: MetodosSesion?
    @State private var entrada: EntradaTelegram?
    @State private var confirmar = false
    @State private var espera: Task<Void, Never>?
    @State private var ocupado = false
    @State private var mensaje: String?

    @State private var nombre = ""
    @State private var toques = 0
    @State private var laboratorio = false

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    private static let whatsapp = "https://wa.me/5492235926772"
    private var version: String {
        let i = Bundle.main.infoDictionary
        return (i?["CFBundleShortVersionString"] as? String ?? "1.0") + " (" + (i?["CFBundleVersion"] as? String ?? "1") + ")"
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: cuenta.activa ? "Cuenta" : "Entrar", sesion: nil, atras: atras)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if cuenta.activa { perfil } else { entrar }
                    if let mensaje { AvisoConsola(texto: mensaje, error: true).padding(.top, 16) }
                    if !cuenta.activa { depurar.padding(.top, 32) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FondoConsola())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: cuenta.servidor) { await cargarMetodos() }
        .task(id: cuenta.activa) { await cargarPerfil() }
        .onDisappear { espera?.cancel() }
        .fullScreenCover(isPresented: $laboratorio) {
            if let s = SesionS1.actual {
                LaboratorioVista(modelo: s.modelo, rack: .expresiones)
            } else {
                EstadoVacio(texto: "Abrí una S1 primero.", expresion: "pensando")
                    .onTapGesture { laboratorio = false }
            }
        }
    }

    private func atras() { if !Navegacion.volver(&ruta) { cerrar() } }

    // MARK: 23 · Cuenta

    @ViewBuilder private var perfil: some View {
        let quien = nombre.isEmpty ? (cuenta.email.isEmpty ? "Vos" : cuenta.email) : nombre
        HStack(spacing: 16) {
            Inicial(nombre: quien, tamano: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(quien).font(S1Tipo.titulo).foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.6)
                Text(cuenta.email.isEmpty ? "Entraste con Telegram" : "Entraste con tu mail").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
            }
            Spacer(minLength: 0)
        }
        Seccion("Suscripción de IA")
        TarjetaS1 {
            HStack {
                Text("Charlar con Claude").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                Spacer()
                Text("Pronto").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta2)
            }
            Text("Por ahora, gratis.").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
        }
        Seccion("Ayuda")
        VStack(spacing: 0) {
            Button { if let u = URL(string: Self.whatsapp) { abrir(u) } } label: {
                FilaS1(titulo: "Escribinos por WhatsApp", detalle: "Te contesta una persona", flecha: true) { IconoEnCirculo(icono: .charla) }
            }
            .buttonStyle(.plain)
            FilaS1(titulo: "Garantía", detalle: "6 meses desde que la recibiste") { IconoEnCirculo(icono: .sistema("checkmark.shield")) }
        }
        BotonS1("Cerrar sesión", naranja: false) {
            Task { await cuenta.api.salir(); cuenta.salir(); EnVivo.compartido.reiniciar() }
        }
        .padding(.top, 32)
        versionAbajo
    }

    /// La versión: siete toques abren el Laboratorio.
    private var versionAbajo: some View {
        Button {
            toques += 1
            if toques >= 7 { toques = 0; laboratorio = true }
        } label: {
            Text(toques >= 3 ? "Versión \(version) · \(7 - toques) más" : "Versión \(version)")
                .font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .sensoryFeedback(.selection, trigger: toques)
    }

    private func cargarPerfil() async {
        guard cuenta.activa, let o = try? await cuenta.api.pedir("/v1/sesion"), let u = o["usuario"] as? [String: Any] else { return }
        nombre = (u["nombre"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: 21 · Entrar

    @ViewBuilder private var entrar: some View {
        MarcoPantalla(tamano: .detalle) { CaraDibujada(expresion: paso == "inicio" ? "contento" : "enamorado") }
            .frame(maxWidth: .infinity)
        switch paso {
        case "telegram":
            Text(confirmar ? "Tocá Crear." : "Andá a Telegram.").font(S1Tipo.display).tracking(-1.5).foregroundStyle(Color.s1Tinta)
                .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 24)
            HStack(spacing: 8) {
                PuntitosPensando()
                Text(confirmar ? "Falta «Crear mi cuenta»" : "Esperando…").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            }
            .padding(.top, 8)
            if let e = entrada, let u = URL(string: e.enlace) {
                BotonS1("Abrir Telegram") { abrir(u) }.padding(.top, 24)
            }
            Seccion("O con el código")
            HStack(spacing: 8) {
                CampoS1(ayuda: "123 456", texto: $codigo, teclado: .numberPad)
                Button { Task { await codigoTelegram() } } label: { Text(ocupado ? "…" : "Entrar") }.tecla()
                    .disabled(ocupado || codigo.filter(\.isNumber).count != 6)
            }
            BotonS1("Volver", naranja: false) { cancelar() }.padding(.top, 24)
        case "mailEnviado":
            Text("Fijate tu mail.").font(S1Tipo.display).tracking(-1.5).foregroundStyle(Color.s1Tinta)
                .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 24)
            CampoS1(ayuda: "El código: XXXX-XXXX", texto: $codigo, teclado: .asciiCapable).padding(.top, 16)
            BotonS1(ocupado ? "Entrando…" : "Entrar") { Task { await entrarConCodigo() } }
                .disabled(ocupado || codigo.replacingOccurrences(of: "-", with: "").count != 8)
                .padding(.top, 16)
            BotonS1("Otro mail", naranja: false) { paso = "inicio"; codigo = ""; mensaje = nil }.padding(.top, 8)
        default:
            Text("Entrá.").font(S1Tipo.display).tracking(-1.76).foregroundStyle(Color.s1Tinta).padding(.top, 24)
            Text(metodos?.email == true ? "Con tu Telegram o tu mail. Sin contraseñas." : "Con tu Telegram. Sin contraseñas.")
                .font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2).padding(.top, 4)
            if metodos?.telegram != false {
                BotonS1(ocupado ? "…" : "Seguir con Telegram") { Task { await conTelegram() } }
                    .disabled(ocupado || metodos == nil)
                    .padding(.top, 24)
            }
            if metodos?.email == true {
                Seccion("O con tu mail")
                CampoS1(ayuda: "vos@ejemplo.com", texto: $email, teclado: .emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                BotonS1(ocupado ? "Mandando…" : "Mandame el código", naranja: false) { Task { await pedirLink() } }
                    .disabled(ocupado || !email.contains("@"))
                    .padding(.top, 8)
            }
        }
    }

    /// El servidor, solo para depurar (por defecto, la nube de Sintética).
    private var depurar: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                CampoVisor(rotulo: "", texto: $servidor, ayuda: Cuenta.servidorPorDefecto, claro: true, teclado: .URL) {
                    let v = servidor.trimmingCharacters(in: .whitespaces)
                    if v.hasPrefix("http"), v != cuenta.servidor, !cuenta.activa { cuenta.servidor = v }
                }
                if servidor != Cuenta.servidorPorDefecto, !cuenta.activa {
                    BotonS1("La de Sintética", naranja: false) { servidor = Cuenta.servidorPorDefecto; cuenta.servidor = servidor }
                }
            }
            .padding(.top, 8)
        } label: { Text("Servidor").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2) }
        .tint(Color.s1Tinta2)
        .disabled(cuenta.activa)
    }

    private func cargarMetodos() async {
        do {
            metodos = try await cuenta.api.metodos()
        } catch {
            metodos = MetodosSesion(email: true, telegram: false, bot: "")
        }
    }

    private func conTelegram() async {
        ocupado = true
        mensaje = nil
        defer { ocupado = false }
        do {
            let e = try await cuenta.api.pedirEntradaTelegram()
            entrada = e
            confirmar = false
            codigo = ""
            paso = "telegram"
            if let u = URL(string: e.enlace) { abrir(u) }
            esperar(e)
        } catch {
            mensaje = error.localizedDescription
        }
    }

    /// Espera a que toque Start (la API contesta en cuanto pasa, o a los 25 s).
    private func esperar(_ e: EntradaTelegram) {
        espera?.cancel()
        espera = Task {
            while !Task.isCancelled, paso == "telegram" {
                do {
                    switch try await cuenta.api.esperarEntradaTelegram(e) {
                    case let .adentro(t): adentro(t); return
                    case .confirmar: confirmar = true
                    case .pendiente: break
                    case .vencio:
                        mensaje = "Venció. Pedí otro."
                        paso = "inicio"
                        return
                    }
                } catch {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    private func codigoTelegram() async {
        guard let e = entrada else { return }
        ocupado = true
        mensaje = nil
        defer { ocupado = false }
        do { adentro(try await cuenta.api.codigoEntradaTelegram(e, codigo.filter(\.isNumber))) } catch { mensaje = error.localizedDescription }
    }

    private func adentro(_ token: String) {
        espera?.cancel()
        cuenta.entrar(token)
        EnVivo.compartido.reiniciar()
        paso = "inicio"
        entrada = nil
        codigo = ""
    }

    private func cancelar() {
        espera?.cancel()
        paso = "inicio"
        mensaje = nil
    }

    private func pedirLink() async {
        ocupado = true
        defer { ocupado = false }
        cuenta.email = email.trimmingCharacters(in: .whitespaces)
        do {
            try await cuenta.api.pedirEnlace(cuenta.email)
            paso = "mailEnviado"
            mensaje = nil
        } catch { mensaje = error.localizedDescription }
    }

    private func entrarConCodigo() async {
        ocupado = true
        defer { ocupado = false }
        do {
            adentro(try await cuenta.api.canjear(email: cuenta.email, codigo: codigo))
        } catch { mensaje = error.localizedDescription }
    }
}

/// El link del mail abrió la app: sintetica://entrar?t=…
@MainActor
func entrarConLink(_ url: URL) async -> String? {
    guard url.scheme == "sintetica", url.host == "entrar",
          let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value else { return nil }
    do {
        let c = Cuenta.compartida
        c.entrar(try await c.api.canjear(tokenEnlace: t))
        EnVivo.compartido.reiniciar()
        return "Entraste."
    } catch {
        return error.localizedDescription
    }
}
