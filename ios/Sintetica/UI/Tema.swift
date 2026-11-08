import CoreText
import SwiftUI
import UIKit

/// Los tokens del manual de marca: tema Claro y tema Pantalla.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func token(_ claro: UInt32, _ oscuro: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: oscuro)) : UIColor(Color(hex: claro)) })
    }

    static let papel = token(0xFBFAF7, 0x0E0D0C)
    static let papelAlto = token(0xFFFFFF, 0x1A1816)
    static let linea = token(0xE6E2DA, 0x2C2925)
    static let tinta = token(0x141210, 0xF5F2EC)
    static let tintaSuave = token(0x6B6660, 0xA39E96)
    static let naranja = token(0xF5501A, 0xFF6A33)
    static let naranjaProfundo = token(0xB83C0C, 0xFF8A5C)
    static let naranjaClaro = token(0xFFE3D6, 0x4A2416)
    static let sobreNaranja = Color(hex: 0x141210)
    static let pantalla = Color(hex: 0x0B0A09)
    static let carcasa = token(0x1A1816, 0x26231F)
}

/// Fraunces y JetBrains Mono son fuentes variables: se arman con sus ejes.
enum Tipos {
    private static func variable(_ familia: String, _ tamano: CGFloat, _ ejes: [String: CGFloat]) -> Font {
        let nombre = UIFont.fontNames(forFamilyName: familia).first ?? familia
        guard let base = UIFont(name: nombre, size: tamano) else { return .system(size: tamano) }
        var porId: [NSNumber: CGFloat] = [:]
        let axes = (CTFontCopyVariationAxes(base as CTFont) as? [[String: Any]]) ?? []
        for eje in axes {
            guard let id = eje[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                  let etiqueta = eje[kCTFontVariationAxisNameKey as String] as? String else { continue }
            let tag = Self.tag(id.uint32Value)
            if let v = ejes[tag] ?? ejes[etiqueta] { porId[id] = v }
        }
        let d = base.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): porId])
        return Font(UIFont(descriptor: d, size: tamano) as CTFont)
    }

    private static func tag(_ n: UInt32) -> String {
        String(bytes: [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)], encoding: .ascii) ?? ""
    }

    static func fraunces(_ tamano: CGFloat, _ peso: CGFloat) -> Font {
        variable("Fraunces", tamano, ["wght": peso, "SOFT": 100, "WONK": 0, "opsz": min(144, max(9, tamano))])
    }

    static func mono(_ tamano: CGFloat, _ peso: CGFloat) -> Font { variable("JetBrains Mono", tamano, ["wght": peso]) }

    static let display = fraunces(40, 800)
    static let titulo = fraunces(24, 700)
    static let cuerpo = fraunces(17, 400)
    static let chico = fraunces(14, 400)
    static let dato = mono(14, 400)
    static let etiqueta = mono(11, 700)
    static let boton = mono(13, 700)
    static let serie = mono(13, 700)
}
