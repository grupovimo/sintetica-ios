import Foundation
import UIKit

/// Cómo se presenta cada robot: el nombre de producto, la foto real y dónde
/// cae la pantalla en esa foto, y lo que trae. Igual que web/src/lib/consola/modelo.ts.
/// Nada de acá nombra placas ni componentes: solo lo que ve el usuario.
enum Capacidad: String, CaseIterable, Sendable {
    case pantalla, movimiento, bluetooth, wifi, microfono, parlante

    var nombre: String {
        switch self {
        case .pantalla: "Pantalla"
        case .movimiento: "Movimiento"
        case .bluetooth: "Bluetooth"
        case .wifi: "WiFi"
        case .microfono: "Micrófono"
        case .parlante: "Parlante"
        }
    }

    var icono: String {
        switch self {
        case .pantalla: "rectangle.inset.filled"
        case .movimiento: "move.3d"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .wifi: "wifi"
        case .microfono: "mic.fill"
        case .parlante: "speaker.wave.2.fill"
        }
    }
}

/// La foto ocupa una ventana 4:5. `foto` es la posición de la imagen (en % de
/// la ventana: ancho e izquierda del ancho, arriba del alto) y `pantalla` la
/// caja de la pantalla encima de esa imagen.
struct Encuadre: Equatable, Sendable {
    struct Foto: Equatable, Sendable { let ancho: Double, izq: Double, arriba: Double }
    struct Caja: Equatable, Sendable { let izq: Double, arriba: Double, ancho: Double, alto: Double }
    let imagen: String
    let alt: String
    let foto: Foto
    let pantalla: Caja
    let fondo: UInt32

    static let rectangular = Encuadre(imagen: "unidad", alt: "La Unidad sobre un escritorio",
                                      foto: Foto(ancho: 100, izq: 0, arriba: 0),
                                      pantalla: Caja(izq: 23.5, arriba: 29.5, ancho: 43.5, alto: 39.5), fondo: 0xE9E2D8)
    static let redonda = Encuadre(imagen: "pieza-colgante", alt: "El robot colgado de una cadena",
                                  foto: Foto(ancho: 160, izq: -28.2, arriba: -43.1),
                                  pantalla: Caja(izq: 26.8, arriba: 36.9, ancho: 46.2, alto: 37), fondo: 0xF3EEEA)

    /// Una pantalla apaisada en una caja bien de pie (en la ventana 4:5): se
    /// agranda al 185 % para que la cara llene el ancho, como en la web. Con la
    /// foto de la Unidad no hace falta.
    func apaisada(redonda: Bool) -> Bool { !redonda && pantalla.alto * 5 > pantalla.ancho * 4 * 1.5 }

    /// Alto / ancho de la foto (las dos son 4:5).
    @MainActor
    static func proporcion(_ imagen: String) -> CGFloat {
        guard let i = UIImage(named: imagen), i.size.width > 0 else { return 1.25 }
        return i.size.height / i.size.width
    }
    static let agrandado = 1.85
}

struct ModeloProducto: Equatable, Sendable {
    let nombre: String
    let redonda: Bool
    let encuadre: Encuadre
    let capacidades: Set<Capacidad>
    /// Alto sobre ancho de su pantalla.
    var proporcion: Double = 172.0 / 320

    func tiene(_ c: Capacidad) -> Bool { capacidades.contains(c) }

    /// Los virtuales (y el de prueba) traen todo, así se puede probar cada módulo sin hardware.
    static func de(perfil: String, virtual: Bool, pantalla: Pantalla?) -> ModeloProducto {
        let broche = perfil.contains("broche")
        let redonda = pantalla?.redonda ?? broche
        let todo: Set<Capacidad> = Set(Capacidad.allCases)
        let base: Set<Capacidad> = [.pantalla, .movimiento, .bluetooth, .wifi]
        let prop: Double = pantalla.map { $0.ancho > 0 ? Double($0.alto) / Double($0.ancho) : 172.0 / 320 } ?? 172.0 / 320
        let celu = perfil.contains("celu")
        return ModeloProducto(nombre: broche || (pantalla?.redonda ?? false) ? "Broche" : "Unidad", redonda: redonda,
                              encuadre: redonda ? .redonda : .rectangular, capacidades: virtual || celu ? todo : base, proporcion: prop)
    }
}

/// Cómo ve la pantalla cada perfil (también los virtuales).
func pantallaDe(perfil: String, estado: Estado?) -> Pantalla {
    if let p = estado?.pantalla, p.ancho > 0 { return p }
    return perfil.contains("broche") ? Pantalla(ancho: 240, alto: 240, redonda: true) : Pantalla(ancho: 320, alto: 172, redonda: false)
}

/// "Nº 001": los últimos dígitos del id, para grabar en la placa.
func numeroDe(_ id: String) -> String {
    let hexa = id.uppercased().filter { "0123456789ABCDEF".contains($0) }
    let n = (Int(String(hexa.suffix(4)), radix: 16) ?? 0) % 1000
    return "Nº " + String(format: "%03d", n)
}

/// El ánimo en palabras, a partir del humor (-1..1).
func animoDe(_ e: Estado?, conectado: Bool) -> String {
    guard let e else { return conectado ? "Despertando" : "Sin noticias" }
    if e.dormido { return "Durmiendo" }
    if e.actualizando { return "Actualizándose" }
    if e.humor > 0.5 { return "Muy contento" }
    if e.humor > 0.15 { return "Contento" }
    if e.humor < -0.5 { return "Bajoneado" }
    if e.humor < -0.15 { return "Medio molesto" }
    return "Tranquilo"
}

func hace(_ fecha: Date?, ahora: Date = Date()) -> String {
    guard let fecha else { return "nunca" }
    let s = ahora.timeIntervalSince(fecha)
    if s < 90 { return "recién" }
    if s < 3600 { return "hace \(Int((s / 60).rounded())) min" }
    if s < 86400 { return "hace \(Int((s / 3600).rounded())) h" }
    return "hace \(Int((s / 86400).rounded())) días"
}
