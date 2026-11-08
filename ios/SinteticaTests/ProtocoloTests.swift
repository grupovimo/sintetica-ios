import XCTest
@testable import Sintetica

/// El protocolo de la app contra shared/protocolo/vectores.json (los que entiende el núcleo C++).
final class ProtocoloTests: XCTestCase {
    private var v: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vectores", withExtension: "json"))
        v = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func lista(_ k: String) -> [[String: Any]] { v[k] as? [[String: Any]] ?? [] }

    func testComandos() throws {
        let c = Dictionary(uniqueKeysWithValues: lista("comandos").map { ($0["nombre"] as! String, $0) })
        func esperado(_ n: String) -> String { c[n]!["hex"] as! String }
        XCTAssertEqual(hex(Comando.expresion("enamorado")), esperado("expresion enamorado"))
        XCTAssertEqual(hex(Comando.expresion()), esperado("expresion automatica"))
        XCTAssertEqual(hex(Comando.nombre("Toto")), esperado("nombre Toto"))
        XCTAssertEqual(hex(Comando.nombre("Ñandú")), esperado("nombre con tilde"))
        XCTAssertEqual(hex(Comando.evento("sacudida")), esperado("evento sacudida"))
        XCTAssertEqual(hex(Comando.vincular("K7Q2XM")), esperado("vincular"))
        XCTAssertEqual(hex(Comando.autenticar(deHex(c["autenticar"]!["clave"] as! String))), esperado("autenticar"))
        XCTAssertEqual(hex(Comando.desvincular()), esperado("desvincular"))
        XCTAssertEqual(hex(Comando.pedirConfig()), esperado("pedir config"))
        XCTAssertEqual(hex(ComandoImagen.borrar(3)), esperado("imagen borrar 3"))
        XCTAssertEqual(hex(ComandoImagen.listar()), esperado("imagen listar"))
        XCTAssertEqual(hex(ComandoImagen.pedir(5)), esperado("imagen pedir 5"))
        XCTAssertEqual(hex(Comando.red(c["red"]!["ssid"] as! String, clave: c["red"]!["clave"] as! String)), esperado("red"))
        XCTAssertEqual(hex(Comando.red("Bar")), esperado("red abierta"))
        let n = c["nube"]!
        XCTAssertEqual(hex(Comando.nube(url: n["url"] as! String, usuario: n["usuario"] as! String, clave: n["clave"] as! String)), esperado("nube"))
        XCTAssertEqual(hex(Comando.olvidarRed()), esperado("olvidar red"))
        XCTAssertEqual(hex(Comando.reproducir("saludo")), esperado("reproducir saludo"))
        XCTAssertEqual(hex(Comando.reproducir()), esperado("reproducir parar"))
        XCTAssertEqual(hex(ComandoOta.cancelar()), esperado("ota cancelar"))
        // v1.4
        XCTAssertEqual(hex(Comando.hora(epochUtc: 1_793_000_000, zonaMinutos: -180)), esperado("hora"))
        XCTAssertEqual(hex(Comando.vida()), esperado("vida"))
        XCTAssertEqual(hex(Comando.vida(superposicion: true)), esperado("vida superposicion"))
        XCTAssertEqual(hex(Comando.memoria()), esperado("memoria"))
        XCTAssertEqual(hex(Comando.registro()), esperado("registro"))
        XCTAssertEqual(hex(Comando.evento("sacudida-fuerte")), esperado("evento sacudida-fuerte"))
        XCTAssertEqual(hex(Comando.comportamiento("practicar-caras")), esperado("comportamiento practicar-caras"))
    }

    func testOta() {
        let o = v["ota"] as! [String: Any]
        let bin = deHex(o["binario"] as! String)
        let m = Manifiesto(tamano: UInt32(bin.count), sha256: deHex(o["sha256"] as! String), firma: deHex(o["firma"] as! String),
                           version: o["version"] as! String, perfil: o["perfil"] as! String)
        XCTAssertEqual(hex(m.bytes), o["manifiesto"] as? String)
        XCTAssertEqual(hex(ComandoOta.descargar(m, url: o["url"] as! String)), o["descargar"] as? String)
        XCTAssertEqual(ComandoOta.escrituras(m, bin, tamanoBloque: o["tamanoBloque"] as! Int).map(hex), o["escrituras"] as? [String])
        XCTAssertEqual(leerProgresoOta([0xB4, 0, 40])?.porcentaje, 40)
    }

    func testConfigEnBloques() {
        let c = v["config"] as! [String: Any]
        let esperadas = c["escrituras"] as! [String]
        XCTAssertEqual(escriturasDeConfig(c["json"] as! String, tamanoBloque: c["tamanoBloque"] as! Int).map(hex), esperadas)
    }

    func testEstados() throws {
        for e in lista("estados") {
            let c = e["campos"] as! [String: Any]
            let est = try leerEstado(deHex(e["hex"] as! String))
            XCTAssertEqual(est.bateria, c["bateria"] as? Int)
            XCTAssertEqual(est.humor, Float((c["humor"] as! NSNumber).doubleValue), accuracy: 0.011)
            XCTAssertEqual(est.modo, c["modo"] as? String)
            XCTAssertEqual(est.dormido, c["dormido"] as? Bool)
            XCTAssertEqual(est.fija, c["fija"] as? Bool)
            XCTAssertEqual(est.emparejando, c["emparejando"] as? Bool)
            XCTAssertEqual(est.autenticado, c["autenticado"] as? Bool)
            XCTAssertEqual(est.expresion, c["expresion"] as? String)
            XCTAssertEqual(est.nombre, c["nombre"] as? String)
            XCTAssertEqual(est.serie, c["serie"] as? String)
            XCTAssertEqual(est.id, c["id"] as? String)
            XCTAssertEqual(est.pantalla.ancho, c["ancho"] as? Int)
            XCTAssertEqual(est.pantalla.alto, c["alto"] as? Int)
            XCTAssertEqual(est.pantalla.redonda, c["redonda"] as? Bool)
            XCTAssertEqual(est.wifi, c["wifi"] as? Bool)
            XCTAssertEqual(est.nube, c["nube"] as? Bool)
            XCTAssertEqual(est.redConfigurada, c["redConfigurada"] as? Bool)
            XCTAssertEqual(est.actualizando, c["actualizando"] as? Bool)
            XCTAssertEqual(est.version, c["version"] as? String)
            XCTAssertEqual(est.perfil, c["perfil"] as? String)
            XCTAssertEqual(est.crcConfig, UInt32(c["crcConfigHex"] as! String, radix: 16))
            XCTAssertEqual(est.encendido, UInt32(c["encendido"] as! Int))
        }
    }

    func testRespuestas() {
        for r in lista("respuestas") {
            guard case let .resultado(op, codigo, detalle, clave) = leerRespuesta(deHex(r["hex"] as! String)) else { return XCTFail() }
            XCTAssertEqual(Int(op), r["op"] as? Int)
            XCTAssertEqual(Int(codigo), r["codigo"] as? Int)
            if let k = r["clave"] as? String { XCTAssertEqual(clave, deHex(k)) }
            if let d = r["detalle"] as? String { XCTAssertEqual(detalle, d) }
        }
    }

    func testQrYAnuncio() {
        for q in lista("qr") {
            let l = leerQr(q["texto"] as! String)
            if let id = q["id"] as? String {
                XCTAssertEqual(l?.id, id)
                XCTAssertEqual(l?.codigo, q["codigo"] as? String)
            } else { XCTAssertNil(l) }
        }
        for a in lista("anuncios") { XCTAssertEqual(idDeAnuncio(deHex(a["hex"] as! String)), a["id"] as? String) }
    }

    func testQoiIgualAlDeReferencia() {
        let q = v["qoi"] as! [String: Any]
        let qoi = Qoi.codificar(deHex(q["rgb"] as! String), ancho: q["ancho"] as! Int, alto: q["alto"] as! Int)
        XCTAssertEqual(hex(qoi), q["hex"] as? String)
        let escrituras = escriturasDeImagen(q["espacio"] as! Int, qoi, tamanoBloque: q["tamanoBloque"] as! Int).map(hex)
        XCTAssertEqual(escrituras, q["escrituras"] as? [String])
    }

    func testCrc() {
        for c in lista("crc32") { XCTAssertEqual(String(format: "%08x", crc32(Array((c["texto"] as! String).utf8))), c["crc"] as? String) }
    }

    func testArmadorDeConfig() throws {
        let texto = "{\"version\":1,\"nombre\":\"Ñandú\"}"
        let b = Array(texto.utf8)
        var a = ArmadorDeConfig()
        XCTAssertNil(try a.agregar(.trozo(desplazamiento: 0, datos: Array(b[0 ..< 10]))))
        XCTAssertNil(try a.agregar(.trozo(desplazamiento: 10, datos: Array(b[10...]))))
        XCTAssertEqual(try a.agregar(.cierre(largo: b.count, crc: crc32(b))), texto)
    }
}
