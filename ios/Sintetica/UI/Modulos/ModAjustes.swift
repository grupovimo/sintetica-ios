import SwiftUI

/// Ajustes: su nombre, el brillo, y lo de fondo (laboratorio, cerca por
/// Bluetooth, sacarlo de la cuenta). Como web/src/lib/consola/modulos/Ajustes.svelte.
struct ModAjustes: View {
    let modelo: ModeloRobot
    let laboratorio: () -> Void
    let cerca: () -> Void
    let volver: () -> Void
    @State private var nombre = ""
    @State private var error = ""
    @State private var seguro = false
    @State private var quitando = false

    var body: some View {
        let e = modelo.estado
        let c = modelo.config
        VStack(spacing: 16) {
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            CampoVisor(rotulo: "Se llama", texto: $nombre, ayuda: "Ponele nombre") {
                let n = nombre
                if n != modelo.nombre { Task { error = await modelo.ponerApodo(n) ?? "" } }
            }
            .onChange(of: nombre) { _, v in let x = cortarBytes(v, 24); if x != v { nombre = x } }
            Bandeja {
                Perilla(nombre: "Brillo", valor: c.brilloMax, min: 0.2, max: 1, mostrar: { "\(Int(($0 * 100).rounded()))%" }, tamano: 64) { v in
                    modelo.cambiar { $0.ponerBrillo(v) }
                }
                .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                dato("Modelo", "\(modelo.producto.nombre) \(numeroDe(modelo.id))")
                dato("Firmware", (e?.version).flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                dato("Config", modelo.esNube ? "v\(modelo.versionConfig)" : "En el robot")
                dato("Batería", e?.bateria.map { "\($0)%" } ?? "—")
                dato("WiFi", e?.wifi == true ? "Conectado" : "No")
                dato("Serie", modelo.esDemo ? "—" : modelo.id)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Flujo(espacio: 10, renglon: 6) {
                Button(action: laboratorio) { Label("Laboratorio", systemImage: "flask.fill") }.tecla(.negra)
                if modelo.vinculado || modelo.esBle {
                    Button(action: cerca) { Label("Cerca", systemImage: "dot.radiowaves.left.and.right") }.tecla()
                }
            }
            Bandeja {
                HStack {
                    Text(modelo.esNube ? "SACARLO DE TU CUENTA" : modelo.esDemo ? "REINICIARLO" : "DESVINCULARLO")
                        .font(Tipos.marca(14, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Button { quitar() } label: { Text(quitando ? "…" : seguro ? "¿Seguro?" : "Sacar") }.tecla(.negra, chica: true).disabled(quitando)
                }
            }
        }
        .onAppear { nombre = modelo.nombre == "Tu robot" ? "" : modelo.nombre }
    }

    private func dato(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Grabado(k)
            Text(v).font(Tipos.marca(13, .heavy)).foregroundStyle(Color.papel).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.hundido)
    }

    private func quitar() {
        if !seguro {
            seguro = true
            Task { try? await Task.sleep(for: .seconds(5)); seguro = false }
            return
        }
        quitando = true
        Task {
            if let e = await modelo.quitar() {
                error = e
                quitando = false
            } else {
                volver()
            }
        }
    }
}
