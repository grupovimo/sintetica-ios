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
        h.ahora_ms = { _ in
            let ms: Int = Int(Date().timeIntervalSince(Nucleo.inicioSinAislar) * 1000) + Nucleo.adelantoMs
            return UInt32(truncatingIfNeeded: ms)
        }
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
    /// Cuánto se adelantó el reloj del núcleo (para sacar fotos de caras sin
    /// esperar los fundidos). Solo crece: el tiempo del núcleo nunca vuelve atrás.
    nonisolated(unsafe) static var adelantoMs = 0

    /// Fotos de caras (también los dibujos con formas) con la instancia: fija
    /// cada una, adelanta el reloj hasta que termina el fundido y saca el cuadro.
    /// Después hay que volver a pasarle su config.
    static func fotografiar(config: String, nombres: [String]) -> [String: CGImage] {
        for e in escriturasDeConfig(config, tamanoBloque: 512) { bleEscribir(Car.config.rawValue, Data(e)) }
        var fotos: [String: CGImage] = [:]
        for n in nombres {
            bleEscribir(Car.comando.rawValue, Data(Comando.expresion(n)))
            for _ in 0 ..< 6 {
                adelantoMs += 200
                tick()
            }
            if let i = imagen() { fotos[n] = i }
        }
        bleEscribir(Car.comando.rawValue, Data(Comando.expresion("")))
        return fotos
    }

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

    /// Valida una config con el mismo núcleo del robot. nil = válida; si no, por qué.
    static func validar(_ json: String) -> String? {
        var detalle = [CChar](repeating: 0, count: 256)
        let n = json.utf8.count
        let r = json.withCString { sintetica_validar_config($0, n, &detalle, 256) }
        if r == 0 { return nil }
        let d = String(cString: detalle)
        return d.isEmpty ? "El robot no aceptaría esta config." : d
    }

    /// Dibuja una cara paramétrica sin tocar la instancia (miniaturas, el
    /// laboratorio y el dock). nil si no hay una cara paramétrica con ese nombre.
    static func dibujarExpresion(config: String?, nombre: String, ancho: Int, alto: Int, redonda: Bool, t: Double) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: ancho * alto * 4)
        var detalle = [CChar](repeating: 0, count: 128)
        let texto = config ?? ""
        let n = texto.utf8.count
        let r: Int32 = texto.withCString { c in
            nombre.withCString { nom in
                sintetica_dibujar_expresion(n > 0 ? c : nil, n, nom, Int32(ancho), Int32(alto), redonda ? 1 : 0, Float(t), &rgba, &detalle, 128)
            }
        }
        if r > 0, config != nil { return dibujarExpresion(config: nil, nombre: nombre, ancho: ancho, alto: alto, redonda: redonda, t: t) }
        guard r == 0 else { return nil }
        return imagenRGBA(rgba, ancho: ancho, alto: alto)
    }

    static func imagenRGBA(_ rgba: [UInt8], ancho w: Int, alto h: Int) -> CGImage? {
        guard let proveedor = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: proveedor, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

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
