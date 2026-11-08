import SwiftUI

/// "demo" = probar sin bicho (el núcleo corre en el celu).
let ID_DEMO = "demo"
let ID_DEMO_BROCHE = "demo-broche"

enum Ruta: Hashable {
    case escanear
    case vinculando(DatosQr)
    case bicho(String)
    case cuenta
}

/// "nube:<id>" = un bicho de la cuenta, lejos: por la API en vez de BLE.
let PREFIJO_NUBE = "nube:"

@main
struct SinteticaApp: App {
    @State private var ruta: [Ruta] = []
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $ruta) {
                Inicio(ruta: $ruta)
                    .navigationDestination(for: Ruta.self) { r in
                        switch r {
                        case .escanear: Escanear(ruta: $ruta)
                        case let .vinculando(qr): Vinculando(qr: qr, ruta: $ruta)
                        case let .bicho(id): BichoVista(id: id, ruta: $ruta)
                        case .cuenta: CuentaVista(ruta: $ruta)
                        }
                    }
            }
            .tint(Color.naranja)
            .onOpenURL { url in
                Task {
                    if await entrarConLink(url) != nil { ruta = [.cuenta] }
                }
            }
        }
    }
}
