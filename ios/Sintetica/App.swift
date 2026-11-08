import SwiftUI

/// "demo" = probar sin robot (el núcleo corre en el celu).
let ID_DEMO = "demo"
let ID_DEMO_BROCHE = "demo-broche"

enum Ruta: Hashable {
    case escanear
    case vinculando(DatosQr)
    case robot(String)
    case cuenta
}

@main
struct SinteticaApp: App {
    @State private var ruta: [Ruta] = []
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $ruta) {
                MisRobots(ruta: $ruta)
                    .navigationDestination(for: Ruta.self) { r in
                        switch r {
                        case .escanear: Escanear(ruta: $ruta)
                        case let .vinculando(qr): Vinculando(qr: qr, ruta: $ruta)
                        case let .robot(id): ConsolaVista(id: id, ruta: $ruta)
                        case .cuenta: CuentaVista(ruta: $ruta)
                        }
                    }
            }
            .tint(Color.brasa)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                Task {
                    if await entrarConLink(url) != nil { ruta = [.cuenta] }
                }
            }
        }
    }
}
