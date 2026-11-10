import Foundation

/// Reparte las notificaciones a varios oyentes (cada uno con su AsyncStream).
@MainActor
final class Difusor {
    private var oyentes: [UUID: AsyncStream<(Car, [UInt8])>.Continuation] = [:]

    func escuchar() -> AsyncStream<(Car, [UInt8])> {
        AsyncStream { c in
            let id = UUID()
            oyentes[id] = c
            c.onTermination = { _ in Task { @MainActor in self.oyentes[id] = nil } }
        }
    }

    func emitir(_ car: Car, _ datos: [UInt8]) { for c in oyentes.values { c.yield((car, datos)) } }
}

/// Por dónde se le habla a un bicho: BLE de verdad o el bicho virtual.
@MainActor
protocol Transporte: AnyObject {
    var difusor: Difusor { get }
    func conectar() async throws
    func escribir(_ car: Car, _ datos: [UInt8]) async throws
    /// Sin esperar la confirmación de cada escritura (los bloques de las imágenes).
    func escribirRapido(_ car: Car, _ datos: [UInt8]) async throws
    /// El bloque más grande que entra en una escritura rápida.
    var tamanoBloque: Int { get }
    func leerEstado() async throws -> [UInt8]
    func cerrar()
}

extension Transporte {
    func escribirRapido(_ car: Car, _ datos: [UInt8]) async throws { try await escribir(car, datos) }
    var tamanoBloque: Int { 180 }
}

/// "Probar sin bicho": el núcleo corre en el celu y se le habla con los mismos bytes que por BLE.
@MainActor
final class TransporteVirtual: Transporte {
    let difusor = Difusor()
    private let anfitrion = AnfitrionEnMemoria()
    private let broche: Bool

    init(broche: Bool = false) { self.broche = broche }

    func conectar() async throws {
        anfitrion.alNotificar = { [difusor] c, d in if let car = Car(rawValue: c) { difusor.emitir(car, Array(d)) } }
        // Al doble de la pantalla, para que se vea nítido; las imágenes se recortan a este tamaño.
        if broche {
            Nucleo.iniciar(ancho: 480, alto: 480, identificador: "000000000000", anfitrion: anfitrion, redonda: true, broche: true)
        } else {
            Nucleo.iniciar(identificador: "000000000000", anfitrion: anfitrion)
        }
        Nucleo.vistaPrevia()
        Nucleo.bleConexion(true)
    }

    func escribir(_ car: Car, _ datos: [UInt8]) async throws { Nucleo.bleEscribir(car.rawValue, Data(datos)) }
    func leerEstado() async throws -> [UInt8] { Array(Nucleo.estado()) }
    func cerrar() {}
}
