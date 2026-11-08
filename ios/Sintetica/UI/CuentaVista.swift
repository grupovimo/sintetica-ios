import SwiftUI

/// La cuenta en la nube: entrar con el link mágico (o su código).
@MainActor
struct CuentaVista: View {
    @Binding var ruta: [Ruta]
    private var cuenta = Cuenta.compartida
    @State private var servidor = Cuenta.compartida.servidor
    @State private var email = Cuenta.compartida.email
    @State private var codigo = ""
    @State private var pedido = false
    @State private var ocupado = false
    @State private var mensaje: String?

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { ruta = [] } label: { Label("Mis robots", systemImage: "chevron.left") }.tecla(.negra, chica: true)
                Grabado("Tu cuenta", color: .brasa)
                if cuenta.activa {
                    Titular(cuenta.email.isEmpty ? "Adentro" : cuenta.email, tamano: 30)
                    Visor(relleno: 12) {
                        Grabado("Servidor")
                        Text(cuenta.servidor).font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(1).truncationMode(.middle)
                    }
                    Button { Task { await cuenta.api.salir(); cuenta.salir(); EnVivo.compartido.reiniciar() } } label: { Text("Salir") }.tecla(.negra)
                } else {
                    Titular("Entrá", tamano: 40)
                    CampoVisor(rotulo: "Servidor", texto: $servidor, ayuda: "https://…", claro: true, teclado: .URL)
                    CampoVisor(rotulo: "Email", texto: $email, ayuda: "vos@mail.com", claro: true, teclado: .emailAddress)
                    Button { Task { await pedirLink() } } label: { Label("Mandame el link", systemImage: "envelope.fill") }
                        .tecla(.naranja, ancha: true)
                        .disabled(ocupado || !email.contains("@") || !servidor.hasPrefix("http"))
                    if pedido {
                        CampoVisor(rotulo: "Código del mail", texto: $codigo, ayuda: "XXXX-XXXX", teclado: .asciiCapable)
                        Button { Task { await entrar() } } label: { Text("Entrar") }.tecla(ancha: true)
                            .disabled(ocupado || codigo.replacingOccurrences(of: "-", with: "").count != 8)
                    }
                }
                if let mensaje { AvisoConsola(texto: mensaje) }
            }
            .padding(16)
        }
        .background(FondoConsola())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func pedirLink() async {
        ocupado = true
        defer { ocupado = false }
        cuenta.servidor = servidor.trimmingCharacters(in: .whitespaces)
        cuenta.email = email.trimmingCharacters(in: .whitespaces)
        do {
            try await cuenta.api.pedirEnlace(cuenta.email)
            pedido = true
            mensaje = "Abrí el link o poné el código."
        } catch { mensaje = error.localizedDescription }
    }

    private func entrar() async {
        ocupado = true
        defer { ocupado = false }
        do {
            cuenta.entrar(try await cuenta.api.canjear(email: cuenta.email, codigo: codigo))
            pedido = false
            mensaje = nil
            EnVivo.compartido.reiniciar()
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
