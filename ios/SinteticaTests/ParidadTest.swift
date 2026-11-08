import XCTest
@testable import Sintetica

/// Lo que la app valida de su lado contra shared/formato/paridad/paridad.json:
/// los topes son los del núcleo y los textos se cortan en bytes igual que él.
final class ParidadTest: XCTestCase {
    private struct Corte { let texto: String, max: Int, resultado: String, bytes: Int }

    private var limites: [String: Int] = [:]
    private var cortes: [Corte] = []

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "paridad", withExtension: "json"))
        let p = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let l = try XCTUnwrap(p["limites"] as? [String: Any])
        limites = l.compactMapValues { ($0 as? NSNumber)?.intValue }
        cortes = (p["cortes"] as? [[String: Any]] ?? []).compactMap { c in
            guard let t = c["texto"] as? String, let m = (c["max"] as? NSNumber)?.intValue,
                  let r = c["resultado"] as? String, let b = (c["bytes"] as? NSNumber)?.intValue else { return nil }
            return Corte(texto: t, max: m, resultado: r, bytes: b)
        }
    }

    private func limite(_ k: String) -> Int { limites[k] ?? -1 }

    func testTopes() {
        XCTAssertEqual(MAX_RECORDATORIOS, limite("recordatorios"))
        XCTAssertEqual(MAX_TEXTO_RECORDATORIO, limite("bytesRecordatorio"))
        XCTAssertEqual(MAX_FRASES, limite("frasesPropias"))
        XCTAssertEqual(MAX_TEXTO, limite("bytesFrase"))
        XCTAssertEqual(MAX_AVISOS, limite("avisos"))
        XCTAssertEqual(MAX_DECIR_AVISO, limite("bytesDecirAviso"))
        XCTAssertEqual(MAX_NOMBRE_AVISO, limite("bytesAppAviso"))
        XCTAssertEqual(MAX_CIUDAD, limite("bytesCiudad"))
        XCTAssertEqual(MAX_PALABRA, limite("bytesPalabra"))
        XCTAssertEqual(MAX_NOMBRE, limite("bytesNombre"))
        XCTAssertEqual(MAX_LISTA, limite("lista"))
        XCTAssertEqual(MAX_REGLAS, limite("reglasUsuario"))
        XCTAssertEqual(Op.maxSprites, limite("sprites"))
    }

    func testCortes() {
        XCTAssertFalse(cortes.isEmpty)
        for c in cortes {
            let r = cortarBytes(c.texto, c.max)
            // Por bytes: String compara por equivalencia canónica y acá importa lo que viaja.
            XCTAssertEqual(Array(r.utf8), Array(c.resultado.utf8), "cortar \"\(c.texto)\" a \(c.max)")
            XCTAssertEqual(r.utf8.count, c.bytes, "bytes de \"\(c.resultado)\"")
        }
    }

    /// Las funciones que cortan con su tope, con los cortes de ese tope.
    func testCortesConSuTope() {
        func deTope(_ k: String) -> [Corte] {
            cortes.filter { $0.max == limite(k) && $0.texto == $0.texto.trimmingCharacters(in: .whitespaces) && !$0.texto.contains("  ") }
        }
        for c in deTope("bytesFrase") { XCTAssertEqual(armarFrase(c.texto, dueno: "", robot: ""), c.resultado) }
        for c in deTope("bytesCiudad") {
            var d = ConfigDoc()
            d.ponerUbicacion(Ubicacion(lat: -34.6, lon: -58.4, ciudad: c.texto))
            XCTAssertEqual(d.ubicacion?.ciudad ?? "", c.resultado)
        }
        for c in deTope("bytesNombre") {
            var d = ConfigDoc()
            d.ponerNombreDueno(c.texto)
            XCTAssertEqual(d.nombreDueno, c.resultado)
        }
        for c in deTope("bytesDecirAviso") {
            let a = AvisoCelu(["tipo": "notificacion", "decir": c.texto])
            XCTAssertEqual(a.objeto["decir"] as? String ?? "", c.resultado)
        }
        for c in deTope("bytesAppAviso") {
            let a = AvisoCelu(["tipo": "notificacion", "app": c.texto, "contacto": c.texto])
            XCTAssertEqual(a.objeto["app"] as? String ?? "", c.resultado)
            XCTAssertEqual(a.objeto["contacto"] as? String ?? "", c.resultado)
        }
    }
}
