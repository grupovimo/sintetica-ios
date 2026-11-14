import SwiftUI
import UIKit

/// Los tokens del sistema de la app (marca/diseno/APP.md, v1.1): de día la
/// crema (C) y de noche los materiales oscuros (A). Siguen al sistema: cada
/// color se resuelve según el modo claro u oscuro del celu.
extension UIColor {
    convenience init(hex: UInt32, alfa: CGFloat = 1) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alfa)
    }
}

extension Color {
    init(hex: UInt32, alfa: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alfa)
    }

    /// Un color de día y otro de noche.
    init(dia: UInt32, noche: UInt32, alfaDia: CGFloat = 1, alfaNoche: CGFloat = 1) {
        self.init(uiColor: UIColor(dynamicProvider: { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: noche, alfa: alfaNoche) : UIColor(hex: dia, alfa: alfaDia)
        }))
    }

    // --- El sistema S1 ---
    static let s1Fondo = Color(dia: 0xF5F2EC, noche: 0x151311)
    static let s1Superficie = Color(dia: 0xECE8E1, noche: 0x1F1C19)
    static let s1Tinta = Color(dia: 0x0B0A09, noche: 0xF5F2EC)
    static let s1Tinta2 = Color(dia: 0x5C574F, noche: 0xB3ACA2)
    /// Lo que todavía no se escribió (los placeholder).
    static let s1Tinta3 = Color(dia: 0x8E877D, noche: 0x6B645B)
    static let s1Linea = Color(dia: 0x0B0A09, noche: 0xF5F2EC, alfaDia: 0.14, alfaNoche: 0.12)
    static let s1Tecla = Color(dia: 0xFBF9F5, noche: 0x2C2824)
    static let s1TeclaBrillo = Color(dia: 0xFFFFFF, noche: 0x36312C)
    static let s1Canto = Color(dia: 0xBDB5A8, noche: 0x050404)
    static let s1Campo = Color(dia: 0xFFFFFF, noche: 0x0E0D0B)
    /// Lo seleccionado: siempre en tinta invertida.
    static let s1Inv = Color(dia: 0x0B0A09, noche: 0xF5F2EC)
    static let s1InvTexto = Color(dia: 0xF5F2EC, noche: 0x0B0A09)
    static let s1InvCanto = Color(dia: 0x3A3632, noche: 0x8E877D)
    static let s1Apagado = Color(dia: 0xD6D0C6, noche: 0x3A3632)
    /// El naranja como texto (sobre la crema no se lee el de la acción).
    static let s1Acento = Color(dia: 0xC43D0A, noche: 0xFF7A45)
    static let s1Error = Color(dia: 0xC8261E, noche: 0xFF6B5E)
    static let s1LedDespierta = Color(dia: 0x658F0E, noche: 0xC6F05A)
    static let s1LedDurmiendo = Color(dia: 0x7A5FE0, noche: 0xB9A4FF)
    static let s1LedSin = Color(hex: 0x8A847B)
    /// La acción principal (una por pantalla) y la S1.
    static let s1Naranja = Color(hex: 0xFF6A33)
    static let s1NaranjaBrillo = Color(hex: 0xFF7C4A)
    static let s1NaranjaCanto = Color(hex: 0xA8360B)
    /// El texto sobre el naranja: siempre oscuro.
    static let s1TintaFija = Color(hex: 0x0B0A09)
    static let s1Pantalla = Color(hex: 0x050404)

    // --- Los nombres de antes (la consola oscura), ahora sobre el sistema ---
    static let fondo = Color.s1Fondo
    static let chapa = Color.s1Superficie
    static let hundido = Color.s1Superficie
    static let papel = Color.s1Tinta
    static let gris = Color.s1Tinta2
    static let grisClaro = Color.s1Tinta2
    static let hueso = Color.s1Tinta2
    static let tinta2 = Color.s1Tinta2
    static let tinta3 = Color.s1Tinta3
    static let naranja = Color.s1Naranja
    static let brasa = Color.s1Acento
    static let led = Color.s1Naranja
    static let verde = Color.s1LedDespierta
    static let ambar = Color(dia: 0xA86400, noche: 0xFFB347)
    static let rojo = Color.s1Error
    static let tinta = Color.s1Tinta
    static let pantalla = Color(hex: 0x0B0A09)
    static let apagado = Color.s1Apagado
}

/// La letra del sistema: Archivo no viene en la app, así que va la del
/// sistema; ancha solo en el display (el saludo y el onboarding). Dos pesos:
/// 400 y 700. Nada por debajo de 13.
enum S1Tipo {
    static let display = Font.system(size: 44, weight: .bold).width(.expanded)
    static let titulo = Font.system(size: 28, weight: .bold)
    static let seccion = Font.system(size: 17, weight: .bold)
    static let cuerpo = Font.system(size: 15, weight: .regular)
    static let cuerpoFuerte = Font.system(size: 15, weight: .bold)
    static let caption = Font.system(size: 13, weight: .regular)
    static let captionFuerte = Font.system(size: 13, weight: .bold)
    static let dato = Font.system(size: 28, weight: .bold).monospacedDigit()
    static func mono(_ t: CGFloat = 13) -> Font { .system(size: max(13, t), weight: .medium, design: .monospaced) }
}

/// La letra de los módulos (los nombres de antes): ahora sin ancho extra, en
/// 400 o 700, y nunca por debajo de 13.
enum Tipos {
    private static func peso(_ p: Font.Weight) -> Font.Weight {
        p == .black || p == .heavy || p == .semibold ? .bold : p
    }

    static func marca(_ tamano: CGFloat, _ p: Font.Weight = .heavy) -> Font {
        .system(size: max(13, tamano), weight: peso(p))
    }

    static func angosta(_ tamano: CGFloat, _ p: Font.Weight = .heavy) -> Font {
        .system(size: max(13, tamano), weight: peso(p))
    }

    static let titular = S1Tipo.titulo
    static let grabado = S1Tipo.captionFuerte
    static let texto = S1Tipo.cuerpo
    static let chico = S1Tipo.caption
    static let digitos = Font.system(size: 40, weight: .bold).monospacedDigit()
    static let digitosChicos = Font.system(size: 20, weight: .bold).monospacedDigit()
}

/// El fondo de cada pantalla.
struct FondoConsola: View {
    var body: some View {
        Color.s1Fondo.ignoresSafeArea()
    }
}
