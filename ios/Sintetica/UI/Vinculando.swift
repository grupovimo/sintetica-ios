import SwiftUI

@MainActor
struct Vinculando: View {
    let qr: DatosQr
    @Binding var ruta: [Ruta]
    @State private var paso = "Buscando el bicho…"
    @State private var error: String?
    @State private var intento = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Etiqueta("Vincular · \(qr.id)")
            Text(error == nil ? paso : "No se pudo vincular.").font(Tipos.display).foregroundStyle(Color.tinta)
            if let error {
                Aviso(texto: error)
                BotonPrimario(texto: "Probar de nuevo") { intento += 1 }
            } else {
                ProgressView().tint(Color.naranja)
            }
            BotonSecundario(texto: "Volver") { ruta = [] }
            Spacer()
        }
        .padding(24)
        .background(Color.papel.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task(id: intento) { await vincular() }
    }

    private func vincular() async {
        error = nil
        var cliente: ClienteBicho?
        do {
            paso = "Buscando el bicho…"
            let p = try await Central.compartida.buscar(id: qr.id)
            paso = "Conectando…"
            let c = ClienteBicho(TransporteBle(p))
            cliente = c
            try await c.conectar()
            paso = "Vinculando…"
            let clave = try await c.vincular(qr.codigo)
            Vinculados.compartidos.guardar(Vinculado(id: qr.id, nombre: c.estado?.nombre ?? "bicho", serie: c.estado?.serie ?? "", clave: clave))
            c.cerrar()
            ruta = [.bicho(qr.id)]
        } catch {
            cliente?.cerrar()
            self.error = error.localizedDescription
        }
    }
}
