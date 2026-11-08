import Foundation
import UIKit

/// Lo que el núcleo le pide a la app.
@MainActor
protocol Anfitrion: AnyObject {
    func guardar(_ clave: String, _ datos: Data) -> Bool
    func leer(_ clave: String) -> Data?
    func notificar(_ caracteristica: Int, _ datos: Data)
    func registrar(_ mensaje: String)
}

/// Un anfitrión que guarda en memoria (vista previa y bicho virtual).
@MainActor
final class AnfitrionEnMemoria: Anfitrion {
    private var datos: [String: Data] = [:]
    var alNotificar: (Int, Data) -> Void = { _, _ in }
    func guardar(_ clave: String, _ datos: Data) -> Bool { self.datos[clave] = datos; return true }
    func leer(_ clave: String) -> Data? { datos[clave] }
    func notificar(_ caracteristica: Int, _ datos: Data) { alNotificar(caracteristica, datos) }
    func registrar(_ mensaje: String) {}
}

/// El núcleo de SintéticaOS (el mismo C++ del firmware) por su API en C.
/// Hay una sola instancia por proceso: todo pasa en el hilo principal.
@MainActor
enum Nucleo {
    private static weak var anfitrion: Anfitrion?
    private static var identificador: UnsafeMutablePointer<CChar>?

    /// redonda: el broche; broche: con el pulsador del broche (toque = siguiente).
    static func iniciar(ancho: Int = 640, alto: Int = 344, identificador id: String, anfitrion: Anfitrion?,
                        redonda: Bool = false, broche: Bool = false) {
        Self.anfitrion = anfitrion
        free(identificador)
        identificador = strdup(id)
        var h = sintetica_hal()
        h.ahora_ms = { _ in UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince(Nucleo.inicioSinAislar) * 1000)) }
        h.semilla = { _ in UInt32.random(in: .min ... .max) }
        h.minuto_del_dia = { _ in
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            return Int32((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        h.guardar = { _, clave, datos, n in
            guard let clave, let datos else { return 0 }
            let d = Data(bytes: datos, count: n)
            return MainActor.assumeIsolated { Nucleo.anfitrion?.guardar(String(cString: clave), d) ?? false } ? 1 : 0
        }
        h.leer = { _, clave, destino, cap in
            guard let clave, let destino else { return -1 }
            let d = MainActor.assumeIsolated { Nucleo.anfitrion?.leer(String(cString: clave)) }
            guard let d, d.count <= cap else { return -1 }
            d.copyBytes(to: destino, count: d.count)
            return Int32(d.count)
        }
        h.notificar = { _, car, datos, n in
            guard let datos else { return }
            let d = Data(bytes: datos, count: n)
            MainActor.assumeIsolated { Nucleo.anfitrion?.notificar(Int(car), d) }
        }
        h.registrar = { _, m in
            guard let m else { return }
            let s = String(cString: m)
            MainActor.assumeIsolated { Nucleo.anfitrion?.registrar(s) }
        }
        h.identificador = UnsafePointer(identificador)
        sintetica_iniciar_perfil(&h, Int32(ancho), Int32(alto), redonda ? 1 : 0, broche ? 1 : 0)
    }

    nonisolated static let inicioSinAislar = Date()

    static func vistaPrevia() { sintetica_vista_previa() }
    static func tick() { sintetica_tick() }
    static var ancho: Int { Int(sintetica_ancho()) }
    static var alto: Int { Int(sintetica_alto()) }
    static func tacto(_ apretado: Bool) { sintetica_tacto(apretado ? 1 : 0) }
    static func evento(_ e: Int) { sintetica_evento(Int32(e)) }
    static func bleConexion(_ conectado: Bool) { sintetica_ble_conexion(conectado ? 1 : 0) }

    static func bleEscribir(_ car: Int, _ datos: Data) {
        datos.withUnsafeBytes { p in
            sintetica_ble_escribir(Int32(car), p.bindMemory(to: UInt8.self).baseAddress, datos.count)
        }
    }

    static func estado() -> Data {
        var b = [UInt8](repeating: 0, count: 128)
        let n = sintetica_ble_estado(&b, b.count)
        return Data(b.prefix(n))
    }

    static var expresiones: [String] {
        (0 ..< Int(sintetica_cantidad_expresiones())).map { String(cString: sintetica_nombre_expresion(Int32($0))) }
    }
    static var expresionVisible: String { String(cString: sintetica_expresion_visible()) }
    static var version: String { String(cString: sintetica_version()) }
    static var imagenVisible: Int { Int(sintetica_imagen_visible()) }

    /// El último cuadro como imagen (RGBA de 8 bits).
    static func imagen() -> CGImage? {
        let w = ancho, h = alto
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        sintetica_pixeles_rgba(&rgba)
        guard let proveedor = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: proveedor, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
