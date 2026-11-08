import SwiftUI

/// La cara del bicho dibujada por el mismo núcleo C++ que corre en la placa,
/// a 640 × 344 (el doble de la pantalla real, con la misma geometría).
@MainActor
struct VistaPrevia: View {
    let descripcion: String
    var redonda = false
    let alApretar: (Bool) -> Void
    @State private var apretado = false

    var body: some View {
        TimelineView(.animation) { _ in
            let imagen = cuadro()
            Group {
                if let imagen { Image(decorative: imagen, scale: 1).resizable().interpolation(.high) } else { Color.pantalla }
            }
            .aspectRatio(CGFloat(Nucleo.ancho) / CGFloat(max(1, Nucleo.alto)), contentMode: .fit)
            .clipShape(redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
        }
        .padding(redonda ? 22 : 14)
        .background(Color.carcasa, in: redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 24)))
        .accessibilityLabel(descripcion)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !apretado { apretado = true; alApretar(true) } }
            .onEnded { _ in apretado = false; alApretar(false) })
    }

    private func cuadro() -> CGImage? {
        Nucleo.tick()
        return Nucleo.imagen()
    }
}
