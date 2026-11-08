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
                Button("← INICIO") { ruta = [] }.font(Tipos.boton).foregroundStyle(Color.tintaSuave)
                Etiqueta("Tu cuenta")
                if cuenta.activa {
                    Text(cuenta.email.isEmpty ? "Adentro" : cuenta.email).font(Tipos.display).foregroundStyle(Color.tinta)
                    Text("Desde acá y desde la web manejás tus bichos aunque estén lejos.").font(Tipos.cuerpo).foregroundStyle(Color.tintaSuave)
                    FilaDato(etiqueta: "Servidor", valor: cuenta.servidor)
                    BotonSecundario(texto: "Salir") {
                        Task { await cuenta.api.salir(); cuenta.salir() }
                    }
                } else {
                    Text("Entrá con tu email").font(Tipos.display).foregroundStyle(Color.tinta)
                    Text("Sin contraseñas: te llega un link.").font(Tipos.cuerpo).foregroundStyle(Color.tintaSuave)
                    TextField("Servidor", text: $servidor).textInputAutocapitalization(.never).keyboardType(.URL)
                        .autocorrectionDisabled().font(Tipos.dato).textFieldStyle(.roundedBorder)
                    Text("En local: http://<la IP de tu Mac>:8080").font(Tipos.dato).foregroundStyle(Color.tintaSuave)
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        .autocorrectionDisabled().font(Tipos.cuerpo).textFieldStyle(.roundedBorder)
                    BotonPrimario(texto: "Mandame el link") { Task { await pedirLink() } }
                        .disabled(ocupado || !email.contains("@") || !servidor.hasPrefix("http"))
                    if pedido {
                        TextField("Código del mail", text: $codigo).textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().font(Tipos.dato).textFieldStyle(.roundedBorder)
                        BotonSecundario(texto: "Entrar") { Task { await entrar() } }
                            .disabled(ocupado || codigo.replacingOccurrences(of: "-", with: "").count != 8)
                    }
                }
                if let mensaje { Aviso(texto: mensaje) }
            }
            .padding(24)
        }
        .background(Color.papel.ignoresSafeArea())
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
            mensaje = "Te mandamos un link: abrilo en este celu, o escribí el código del mail."
        } catch { mensaje = error.localizedDescription }
    }

    private func entrar() async {
        ocupado = true
        defer { ocupado = false }
        do {
            cuenta.entrar(try await cuenta.api.canjear(email: cuenta.email, codigo: codigo))
            pedido = false
            mensaje = nil
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
        return "Entraste."
    } catch {
        return error.localizedDescription
    }
}
