import SwiftUI

@MainActor
struct Vinculando: View {
    let qr: DatosQr
    @Binding var ruta: [Ruta]
    @State private var paso = "Buscando…"
    @State private var error: String?
    @State private var intento = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Grabado("Vincular · \(numeroDe(qr.id))", color: .brasa)
            Titular(error == nil ? paso : "No se pudo", tamano: 38)
            if let error {
                AvisoConsola(texto: error, error: true)
                Button { intento += 1 } label: { Label("Reintentar", systemImage: "arrow.clockwise") }.tecla(.naranja, ancha: true)
            } else {
                ProgressView().tint(Color.brasa)
            }
            Button { ruta = [] } label: { Text("Volver") }.tecla(.negra, chica: true)
            Spacer()
        }
        .padding(16)
        .background(FondoConsola())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task(id: intento) { await vincular() }
    }

    private func vincular() async {
        error = nil
        var cliente: ClienteBicho?
        do {
            paso = "Buscando…"
            let p = try await Central.compartida.buscar(id: qr.id)
            paso = "Conectando…"
            let c = ClienteBicho(TransporteBle(p))
            cliente = c
            try await c.conectar()
            paso = "Vinculando…"
            let clave = try await c.vincular(qr.codigo)
            Vinculados.compartidos.guardar(Vinculado(id: qr.id, nombre: c.estado?.nombre ?? "Tu robot", serie: c.estado?.serie ?? "", clave: clave))
            c.cerrar()
            ruta = [.robot(qr.id)]
        } catch {
            cliente?.cerrar()
            self.error = error.localizedDescription
        }
    }
}
