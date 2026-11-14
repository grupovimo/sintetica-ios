import SwiftUI

/// "demo" = probar sin robot (el núcleo corre en el celu).
let ID_DEMO = "demo"
let ID_DEMO_BROCHE = "demo-broche"

enum Ruta: Hashable {
    case escanear
    case vinculando(DatosQr)
    /// Abre esa S1 en el Inicio (la elige y vuelve a la raíz).
    case robot(String)
    case cuenta
    case misS1
}

@main
struct SinteticaApp: App {
    @State private var ruta: [Ruta] = []

    init() {
        // La presencia: si iOS relanza la app en segundo plano (Bluetooth o la geocerca), arranca acá.
        PresenciaCelu.compartida.arrancar()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $ruta) {
                RaizS1(ruta: $ruta)
                    .navigationDestination(for: Ruta.self) { r in
                        switch r {
                        case .escanear: Escanear(ruta: $ruta)
                        case let .vinculando(qr): Vinculando(qr: qr, ruta: $ruta)
                        case let .robot(id): AbrirS1(id: id, ruta: $ruta)
                        case .cuenta: CuentaVista(ruta: $ruta)
                        case .misS1: MisS1(ruta: $ruta)
                        }
                    }
            }
            .tint(Color.s1Naranja)
            .onOpenURL { url in
                Task {
                    if await entrarConLink(url) != nil { ruta = [.cuenta] }
                }
            }
        }
    }
}

/// Abrir una S1 desde la ruta: la elige y vuelve a la raíz (el Inicio).
@MainActor
struct AbrirS1: View {
    let id: String
    @Binding var ruta: [Ruta]

    var body: some View {
        Color.s1Fondo.ignoresSafeArea()
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { Navegacion.abrir(id, &ruta) }
    }
}
