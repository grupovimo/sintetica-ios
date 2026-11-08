import SwiftUI

/// Los tokens de la consola (web/src/lib/consola/consola.css): chapa oscura,
/// visores hundidos, teclas mecánicas y la placa naranja anodizada. La app va
/// siempre en oscuro.
extension Color {
    init(hex: UInt32, alfa: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alfa)
    }

    static let fondo = Color(hex: 0x16140F)
    static let chapa = Color(hex: 0x211E1A)
    static let hundido = Color(hex: 0x0E0D0B)
    static let papel = Color(hex: 0xF3EEE8)
    static let gris = Color(hex: 0x8F877C)
    static let grisClaro = Color(hex: 0xB9B1A6)
    static let hueso = Color(hex: 0xD9D2C6)
    static let naranja = Color(hex: 0xFF5A1F)
    static let brasa = Color(hex: 0xFF8A5C)
    static let led = Color(hex: 0xFF6A33)
    static let verde = Color(hex: 0x4ADE80)
    static let ambar = Color(hex: 0xFFB347)
    static let rojo = Color(hex: 0xFF4D4D)
    /// El texto sobre las teclas blancas y la placa naranja.
    static let tinta = Color(hex: 0x1A1714)
    static let pantalla = Color(hex: 0x0B0A09)
    static let apagado = Color(hex: 0x4A443E)
}

/// La letra: la del sistema, ancha y pesada (como Archivo en la web).
enum Tipos {
    static func marca(_ tamano: CGFloat, _ peso: Font.Weight = .heavy) -> Font {
        .system(size: tamano, weight: peso).width(.expanded)
    }

    static func angosta(_ tamano: CGFloat, _ peso: Font.Weight = .heavy) -> Font {
        .system(size: tamano, weight: peso).width(.condensed)
    }

    static let titular = marca(46, .black)
    static let grabado = marca(11, .heavy)
    static let texto = Font.system(size: 15, weight: .semibold)
    static let chico = Font.system(size: 13, weight: .semibold)
    static let digitos = marca(40, .black).monospacedDigit()
    static let digitosChicos = marca(20, .black).monospacedDigit()
}

/// El fondo de la consola: una luz arriba que cae sobre la chapa.
struct FondoConsola: View {
    var body: some View {
        ZStack {
            Color.fondo
            RadialGradient(colors: [Color(hex: 0x2A2622), Color.fondo], center: UnitPoint(x: 0.6, y: 0), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
