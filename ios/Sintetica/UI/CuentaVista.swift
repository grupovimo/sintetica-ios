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

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { if !Navegacion.volver(&ruta) { cerrar() } } label: { Label("Mis robots", systemImage: "chevron.left") }.tecla(.negra, chica: true)
                Grabado("Tu cuenta", color: .brasa)
                if cuenta.activa {
                    Titular(cuenta.email.isEmpty ? "Adentro" : cuenta.email, tamano: 30)
                    Button { Task { await cuenta.api.salir(); cuenta.salir(); EnVivo.compartido.reiniciar() } } label: { Text("Salir") }.tecla(.negra)
                } else {
                    Producto(modelo: ModeloProducto.de(perfil: "unidad", virtual: false, pantalla: nil), radio: 28) {
                        PantallaDibujada(config: nil, expresion: paso == "inicio" ? "contento" : "enamorado", pantalla: Pantalla(), fps: 20)
                    }
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)
                    entrar
                }
                if let mensaje { AvisoConsola(texto: mensaje, error: true) }
                depurar
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FondoConsola())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: cuenta.servidor) { await cargarMetodos() }
        .onDisappear { espera?.cancel() }
    }

    @ViewBuilder private var entrar: some View {
        switch paso {
        case "telegram":
            Titular(confirmar ? "Tocá Crear." : "Andá a Telegram.", tamano: 36)
            if let e = entrada, let u = URL(string: e.enlace) {
                Button { abrir(u) } label: { Label("Abrir Telegram", systemImage: "paperplane.fill") }.tecla(.naranja, ancha: true)
            }
            HStack(spacing: 10) {
                ProgressView().tint(Color.brasa)
                Grabado(confirmar ? "Falta Crear mi cuenta" : "Esperando…")
            }
            CampoVisor(rotulo: "O el código", texto: $codigo, ayuda: "123 456", tamano: 30, teclado: .numberPad)
            Button { Task { await codigoTelegram() } } label: { Text(ocupado ? "…" : "Entrar") }.tecla(ancha: true)
                .disabled(ocupado || codigo.filter(\.isNumber).count != 6)
            Button { cancelar() } label: { Text("Volver") }.tecla(.negra, chica: true)
        case "mail":
            Titular("Entrá.", tamano: 40)
            CampoVisor(rotulo: "Tu email", texto: $email, ayuda: "vos@ejemplo.com", claro: true, teclado: .emailAddress)
            Button { Task { await pedirLink() } } label: { Text(ocupado ? "Mandando…" : "Mandame el link") }
                .tecla(.naranja, ancha: true)
                .disabled(ocupado || !email.contains("@"))
            if metodos?.telegram == true { Button { paso = "inicio" } label: { Text("Volver") }.tecla(.negra, chica: true) }
        case "mailEnviado":
            Titular("Fijate tu mail.", tamano: 40)
            CampoVisor(rotulo: "O el código", texto: $codigo, ayuda: "XXXX-XXXX", teclado: .asciiCapable)
            Button { Task { await entrarConCodigo() } } label: { Text(ocupado ? "Entrando…" : "Entrar") }.tecla(.naranja, ancha: true)
                .disabled(ocupado || codigo.replacingOccurrences(of: "-", with: "").count != 8)
            Button { paso = "mail"; codigo = ""; mensaje = nil } label: { Text("Otro mail") }.tecla(.negra, chica: true)
        default:
            Titular("Entrá.", tamano: 40)
            if metodos?.telegram != false {
                Button { Task { await conTelegram() } } label: { Label(ocupado ? "…" : "Con Telegram", systemImage: "paperplane.fill") }
                    .tecla(.naranja, ancha: true).disabled(ocupado || metodos == nil)
            }
            if metodos?.email == true {
                Button { paso = "mail" } label: { Label("Con mail", systemImage: "envelope.fill") }.tecla(.negra, ancha: true)
            }
            Label("Sin contraseñas", systemImage: "key.slash").font(Tipos.chico).foregroundStyle(Color.gris)
        }
    }

    /// El servidor, solo para depurar (por defecto, la nube de Sintética).
    private var depurar: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                CampoVisor(rotulo: "Servidor", texto: $servidor, ayuda: Cuenta.servidorPorDefecto, claro: true, teclado: .URL) {
                    let v = servidor.trimmingCharacters(in: .whitespaces)
                    if v.hasPrefix("http"), v != cuenta.servidor, !cuenta.activa { cuenta.servidor = v }
                }
                if servidor != Cuenta.servidorPorDefecto, !cuenta.activa {
                    Button { servidor = Cuenta.servidorPorDefecto; cuenta.servidor = servidor } label: { Text("La de Sintética") }.tecla(.negra, chica: true)
                }
            }
            .padding(.top, 8)
        } label: { Grabado("Depurar") }
        .tint(Color.gris)
        .disabled(cuenta.activa)
    }

    private func cargarMetodos() async {
        do {
            let m = try await cuenta.api.metodos()
            metodos = m
            if !m.telegram, m.email, paso == "inicio" { paso = "mail" }
        } catch {
            metodos = MetodosSesion(email: true, telegram: false, bot: "")
            if paso == "inicio" { paso = "mail" }
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
