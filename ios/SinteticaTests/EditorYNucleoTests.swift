import XCTest
@testable import Sintetica

final class EditorConfigTests: XCTestCase {
    private func ejemplo() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config-ejemplo", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testLeeElEjemploDelDoc() throws {
        let a = EditorConfig.leer(try ejemplo())
        XCTAssertEqual(a.nombre, "Toto")
        XCTAssertEqual(a.colorOjos, "#FF6A33")
        XCTAssertEqual(a.energia, 0.6, accuracy: 0.001)
        XCTAssertEqual(a.suenoDesde, "23:30")
        XCTAssertEqual(a.suenoHasta, "08:00")
    }

    func testEscribeSinPerderLoQueNoEdita() throws {
        var a = EditorConfig.leer(try ejemplo())
        a.nombre = "Pochi"; a.tamano = 1.2; a.colorOjos = nil; a.suenoDesde = nil; a.suenoHasta = nil
        let nueva = EditorConfig.escribir(try ejemplo(), a)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(nueva.utf8)) as? [String: Any])
        XCTAssertNotNil(o["expresiones"])
        XCTAssertNotNil(o["reglas"])
        XCTAssertEqual(o["modo"] as? String, "mascota")
        XCTAssertNil((o["cara"] as? [String: Any])?["color"])
        let b = EditorConfig.leer(nueva)
        XCTAssertEqual(b.nombre, "Pochi")
        XCTAssertEqual(b.tamano, 1.2, accuracy: 0.001)
        XCTAssertNil(b.suenoDesde)
    }

    func testListaYRotar() throws {
        var a = EditorConfig.leer(try ejemplo())
        a.lista = ["imagen:0", "cara:guino"]
        a.rotar = 15
        let b = EditorConfig.leer(EditorConfig.escribir(try ejemplo(), a))
        XCTAssertEqual(b.lista, ["imagen:0", "cara:guino"])
        XCTAssertEqual(b.rotar, 15)
    }

    func testHoras() {
        XCTAssertTrue(EditorConfig.hhmmValido("23:30"))
        XCTAssertFalse(EditorConfig.hhmmValido("24:00"))
    }
}

/// El núcleo C++ a través de la API en C, desde Swift.
@MainActor
final class NucleoTests: XCTestCase {
    func testBichoVirtualPorElProtocolo() async throws {
        let t = TransporteVirtual()
        let c = ClienteBicho(t)
        try await c.conectar()
        XCTAssertEqual(Nucleo.expresiones.count, 16)
        XCTAssertEqual(c.estado?.expresion, "neutral")
        try await c.cambiarNombre("Toto")
        try await c.fijarExpresion("enamorado")
        XCTAssertEqual(c.estado?.nombre, "Toto")
        XCTAssertEqual(c.estado?.fija, true)
        let config = try await c.pedirConfig()
        XCTAssertTrue(config.contains("\"version\""))
        var a = EditorConfig.leer(config)
        a.energia = 0.9
        try await c.mandarConfig(EditorConfig.escribir(config, a))
        let final = try await c.pedirConfig()
        XCTAssertEqual(EditorConfig.leer(final).energia, 0.9, accuracy: 0.001)
    }

    func testBrocheVirtualConImagen() async throws {
        let c = ClienteBicho(TransporteVirtual(broche: true))
        try await c.conectar()
        XCTAssertEqual(c.estado?.pantalla, Pantalla(ancho: 480, alto: 480, redonda: true))
        let rgb = [UInt8](repeating: 120, count: 480 * 480 * 3)
        try await c.subirImagen(1, Qoi.codificar(rgb, ancho: 480, alto: 480))
        let espacios = try await c.listarImagenes()
        XCTAssertEqual(espacios.map(\.espacio), [1])
    }

    func testVistaPreviaAlDoble() {
        Nucleo.iniciar(identificador: "A1B2C3D4E5F6", anfitrion: nil)
        Nucleo.vistaPrevia()
        Nucleo.tick()
        XCTAssertEqual(Nucleo.ancho, 640)
        XCTAssertEqual(Nucleo.alto, 344)
        XCTAssertNotNil(Nucleo.imagen())
    }
}
