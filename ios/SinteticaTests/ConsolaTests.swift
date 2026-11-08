import UIKit
import XCTest
@testable import Sintetica

/// Lo que no es UI de la consola: el formato, las automatizaciones, el SSE y los encuadres.
@MainActor
final class FormatoConsolaTests: XCTestCase {
    func testCortarBytes() {
        XCTAssertEqual(cortarBytes("hola", 40), "hola")
        XCTAssertEqual(cortarBytes("Ñandú", 4), "Ñan")  // Ñ = 2 bytes, a y n = 1
        XCTAssertEqual(Array(cortarBytes("Ñandú", 4).utf8).count <= 4, true)
        let largo = String(repeating: "á", count: 30)  // 60 bytes
        let c = cortarBytes(largo, 40)
        XCTAssertEqual(c.utf8.count, 40)
        XCTAssertEqual(c.count, 20)
        XCTAssertEqual(cortarBytes("ab😀c", 5), "ab")  // el emoji ocupa 4: no entra entero
        XCTAssertEqual(cortarBytes("", 40), "")
    }

    func testRecordatoriosIdaYVuelta() {
        var c = ConfigDoc()
        c.recordatorios = [Recordatorio(hora: "08:30", texto: "Pastilla"), Recordatorio(hora: "21:00", dias: "LMX", texto: "Regar", expresion: "contento", sonido: false)]
        let o = (c.raiz["recordatorios"] as? [[String: Any]]) ?? []
        XCTAssertEqual(o.count, 2)
        XCTAssertNil(o[0]["dias"])
        XCTAssertNil(o[0]["activo"])
        XCTAssertEqual(o[1]["dias"] as? String, "LMX")
        XCTAssertEqual(o[1]["sonido"] as? Bool, false)
        let leida = ConfigDoc(texto: c.texto).recordatorios
        XCTAssertEqual(leida, c.recordatorios)
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testDiasComoLaWeb() {
        var r = Recordatorio(hora: "08:00", texto: "x")
        XCTAssertTrue(r.tiene("D"))
        r.alternar("L")  // vacío = todos: se arranca de todos y se saca el lunes
        XCTAssertEqual(r.dias, "MXJVSD")
        r.alternar("L")
        XCTAssertEqual(r.dias, "")
        r.alternar("S"); r.alternar("D")
        XCTAssertEqual(r.dias, "LMXJV")
    }

    func testRecordatorioNuevo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9, minute: 41))!
        let r = Recordatorio.nuevo(ahora: d, calendario: cal)
        XCTAssertEqual(r.hora, "10:00")
        XCTAssertEqual(r.texto, "Tomar agua")
        let tarde = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 10))!
        XCTAssertEqual(Recordatorio.nuevo(ahora: tarde, calendario: cal).hora, "00:00")
    }

    func testListaYProtector() {
        var c = ConfigDoc()
        c.mostrar(2, true)
        XCTAssertEqual(c.lista, ["cara:neutral", "imagen:2"])
        c.mostrar(2, false)
        XCTAssertNil(c.raiz["lista"])
        c.ponerProtector(3)
        XCTAssertEqual(c.protector, 3)
        XCTAssertEqual(c.esperaProtector, 10)
        c.moverEspera(1)
        XCTAssertEqual(c.esperaProtector, 30)
        c.ponerProtector(nil)
        XCTAssertNil(c.raiz["protector"])
    }

    func testAV2YHorario() {
        var c = ConfigDoc(texto: #"{"version":1,"personalidad":{"sueno":"23:30-08:00","energia":0.6}}"#)
        c.aV2()
        XCTAssertEqual(c.raiz["version"] as? Int, 2)
        XCTAssertEqual(c.despierta, "08:00")
        XCTAssertEqual(c.duerme, "23:30")
        XCTAssertNil((c.raiz["personalidad"] as? [String: Any])?["sueno"])
        c.moverHorario(despierta: true, minutos: -15)
        XCTAssertEqual(c.despierta, "07:45")
        XCTAssertEqual(sumarMinutos("23:50", 15), "00:05")
        XCTAssertEqual(sumarMinutos("00:05", -15), "23:50")
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testPresetYRasgos() {
        var c = ConfigDoc()
        c.ponerPreset("picaro")
        XCTAssertEqual(c.preset, "picaro")
        XCTAssertEqual(c.rasgo("picardia"), 0.95, accuracy: 0.001)
        c.ponerRasgo("picardia", 0.5)
        XCTAssertEqual(c.preset, "picaro")
        XCTAssertEqual(c.rasgo("picardia"), 0.5, accuracy: 0.001)
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testReflejos() {
        var r = conectarReflejo([], "tacto", "contento")
        XCTAssertEqual(cablesDe(r), ["tacto": "contento"])
        r = conectarReflejo(r, "tacto", "risa")
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].entonces, ["reflejo:risa"])
        let compleja = Regla(si: "tacto", y: "afecto>0.5", entonces: ["reflejo:contento"])
        r = conectarReflejo(r + [compleja], "tacto", nil)
        XCTAssertEqual(r, [compleja])  // la compleja no se toca
    }

    func testCumple() {
        var c = ConfigDoc()
        c.ponerCumple(robot: false, mes: 2, dia: 31)
        XCTAssertEqual(c.cumpleDueno, "02-29")
        c.ponerCumple(robot: true, mes: 12, dia: 5)
        XCTAssertEqual(c.cumpleRobot, "12-05")
        XCTAssertEqual(partesCumple("12-05").mes, 12)
        c.ponerCumple(robot: false, mes: 0, dia: 0)
        XCTAssertNil(c.raiz["dueno"])
    }
}

@MainActor
final class IntegracionesTests: XCTestCase {
    func testAutomatizacionComoLaWeb() throws {
        let a = Automatizacion(id: "a1", activa: true, cuando: "recordatorio", hacer: [AccionAuto(tipo: "telegram", texto: "{robot}: {texto}")])
        let d = try JSONEncoder().encode(a)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: d) as? [String: Any])
        XCTAssertEqual(Set(o.keys), ["id", "activa", "cuando", "hacer"])  // sin "valor" si no hay
        let h = try XCTUnwrap((o["hacer"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(h.keys), ["tipo", "texto"])
        XCTAssertEqual(h["texto"] as? String, "{robot}: {texto}")
    }

    func testAccionesNuevas() {
        XCTAssertEqual(AccionAuto.nueva("telegram", otro: nil), AccionAuto(tipo: "telegram", texto: "{robot}: {evento}"))
        XCTAssertEqual(AccionAuto.nueva("webhook", otro: nil), AccionAuto(tipo: "webhook", url: "https://"))
        XCTAssertEqual(AccionAuto.nueva("robot", otro: "A1B2C3D4E5F6"), AccionAuto(tipo: "robot", bicho: "A1B2C3D4E5F6", expresion: "contento"))
        let n = Automatizacion.nueva(ahora: Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertTrue(n.id.hasPrefix("a"))
        XCTAssertEqual(n.cuando, "recordatorio")
        XCTAssertEqual(n.hacer.count, 1)
    }

    func testLeerRespuestaDeAutomatizaciones() {
        let json = #"{"automatizaciones":[{"id":"x","activa":false,"cuando":"expresion","valor":"triste","hacer":[{"tipo":"webhook","url":"https://a.b/c"}]}],"historial":[{"evento":"expresion","accion":"webhook","ok":true,"en":"2026-11-08T10:00:00Z"}],"cuandos":["expresion","recordatorio"]}"#
        let r = ApiSintetica.leerAutomatizaciones(Data(json.utf8))
        XCTAssertEqual(r.lista.first?.valor, "triste")
        XCTAssertEqual(r.lista.first?.hacer.first?.url, "https://a.b/c")
        XCTAssertEqual(r.historial.first?.ok, true)
        XCTAssertNotNil(r.historial.first?.en)
        XCTAssertEqual(r.cuandos, ["expresion", "recordatorio"])
    }
}

@MainActor
final class EnVivoTests: XCTestCase {
    func testLectorSSE() {
        var l = LectorSSE()
        XCTAssertNil(l.leer(": latido"))
        XCTAssertNil(l.leer("event: estado"))
        let e = l.leer(#"data: {"tipo":"conexion","bicho":"a1b2c3d4e5f6","datos":{"conectado":true}}"#)
        XCTAssertEqual(e?.tipo, "conexion")
        XCTAssertEqual(e?.bicho, "A1B2C3D4E5F6")
        XCTAssertEqual(e?.datos["conectado"] as? Bool, true)
        XCTAssertNil(l.leer(""))
        XCTAssertNil(l.leer("data: no es json"))
        // Sin el espacio después de los dos puntos también vale.
        XCTAssertEqual(l.leer(#"data:{"tipo":"imagenes","bicho":"X"}"#)?.tipo, "imagenes")
    }

    func testAvisosDelRobot() {
        // [0x9E][0][n] y n registros de 6 bytes: segundos (u32), tipo, dato.
        let recordatorio: [UInt8] = [0x9E, 0, 1, 10, 0, 0, 0, 4, 2]
        XCTAssertEqual(avisosDeMarco(car: 2, recordatorio), [.recordatorio(2)])
        let pomodoro: [UInt8] = [0x9E, 0, 2, 1, 0, 0, 0, 0, 32, 2, 0, 0, 0, 0, 5]
        XCTAssertEqual(avisosDeMarco(car: 2, pomodoro), [.pomodoro])
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9E, 0, 3, 0, 0, 0, 0, 4, 1]), [])  // más de 2: es el registro entero
        XCTAssertEqual(avisosDeMarco(car: 1, recordatorio), [])
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9B, 0, 1]), [])
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9E, 0, 1, 0, 0]), [])  // cortado
    }

    func testEstadoDeJSON() {
        let o: [String: Any] = ["bateria": NSNull(), "humor": 0.4, "modo": "reloj", "dormido": true, "expresion": "contento", "nombre": "Toto",
                                "pantalla": ["ancho": 240, "alto": 240, "redonda": true], "version": "1.4.0"]
        let e = estadoDeJSON(o)
        XCTAssertNil(e?.bateria)
        XCTAssertEqual(e?.dormido, true)
        XCTAssertEqual(e?.pantalla, Pantalla(ancho: 240, alto: 240, redonda: true))
        XCTAssertEqual(e?.version, "1.4.0")
        XCTAssertEqual(animoDe(e, conectado: true), "Durmiendo")
        XCTAssertFalse(esCara("recordatorio:0"))
        XCTAssertTrue(esCara("contento"))
    }
}

@MainActor
final class ProductoTests: XCTestCase {
    func testEncuadres() {
        let u = ModeloProducto.de(perfil: "dev-147b", virtual: false, pantalla: nil)
        XCTAssertEqual(u.nombre, "Unidad")
        XCTAssertEqual(u.encuadre, .rectangular)
        XCTAssertEqual(u.encuadre.imagen, "unidad")
        XCTAssertEqual(u.encuadre.foto.ancho, 100, accuracy: 0.001)
        XCTAssertEqual(u.encuadre.pantalla.izq, 23.5, accuracy: 0.001)
        XCTAssertEqual(u.encuadre.pantalla.alto, 39.5, accuracy: 0.001)
        XCTAssertEqual(u.encuadre.fondo, 0xE9E2D8)
        XCTAssertFalse(u.encuadre.apaisada(redonda: u.redonda))  // con la foto de la Unidad no se agranda
        let dePie = Encuadre(imagen: "x", alt: "", foto: .init(ancho: 100, izq: 0, arriba: 0), pantalla: .init(izq: 0, arriba: 0, ancho: 20, alto: 40), fondo: 0)
        XCTAssertTrue(dePie.apaisada(redonda: false))
        XCTAssertEqual(Encuadre.agrandado, 1.85, accuracy: 0.0001)
        XCTAssertFalse(u.tiene(.microfono))
        XCTAssertTrue(Modulo.voz.bloqueado(u))
        let b = ModeloProducto.de(perfil: "broche-c3", virtual: false, pantalla: nil)
        XCTAssertEqual(b.nombre, "Broche")
        XCTAssertTrue(b.redonda)
        XCTAssertEqual(b.encuadre.imagen, "pieza-colgante")
        XCTAssertFalse(b.encuadre.apaisada(redonda: true))
        let v = ModeloProducto.de(perfil: "virtual", virtual: true, pantalla: nil)
        XCTAssertEqual(v.capacidades.count, 6)
        XCTAssertFalse(Modulo.voz.bloqueado(v))
    }

    func testNumeroYHace() {
        XCTAssertEqual(numeroDe("A1B2C3D4E5F6"), "Nº 870")  // 0xE5F6 = 58870
        XCTAssertEqual(numeroDe("000000000001"), "Nº 001")
        let ahora = Date()
        XCTAssertEqual(hace(ahora.addingTimeInterval(-30), ahora: ahora), "recién")
        XCTAssertEqual(hace(ahora.addingTimeInterval(-600), ahora: ahora), "hace 10 min")
        XCTAssertEqual(hace(nil, ahora: ahora), "nunca")
    }

    func testRostroDeFabrica() {
        let c = Rostro.deFabrica("contento")
        XCTAssertEqual(c["izq.w"] ?? 0, 0.13, accuracy: 0.0001)
        XCTAssertEqual(c["der.smile"] ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(c["gy"] ?? 0, 0.04, accuracy: 0.0001)
        XCTAssertEqual(c["sep"] ?? 0, 0.3, accuracy: 0.0001)
        var v = c
        v["izq.w"] = 0.15
        v["der.w"] = 0.15
        v["mcurve"] = 0.5
        let d = Rostro.documento(v, referencia: c)
        XCTAssertEqual((d["ojo"] as? [String: Any])?["w"] as? Double, 0.15)
        XCTAssertEqual(d["mcurve"] as? Double, 0.5)
        XCTAssertNil(d["izq"])
        XCTAssertGreaterThan(VidaBase.reglas.count, 10)
        XCTAssertNotNil(VidaBase.comportamientos["mirar-alrededor"])
    }

    func testQoiIdaYVuelta() {
        var rgb = [UInt8](repeating: 0, count: 16 * 9 * 3)
        for i in 0 ..< rgb.count { rgb[i] = UInt8((i * 7) % 256) }
        let q = Qoi.codificar(rgb, ancho: 16, alto: 9)
        let d = Qoi.decodificar(q)
        XCTAssertEqual(d?.ancho, 16)
        XCTAssertEqual(d?.alto, 9)
        XCTAssertEqual(d?.rgb, rgb)
    }
}

@MainActor
final class LaboratorioTests: XCTestCase {
    func testLeerVida() throws {
        var b: [UInt8] = [0x9B, 0]
        let estados: [UInt8] = [255, 128, 0, 51, 0, 0, 255]  // los 7 estados
        let rasgos: [UInt8] = [128, 128, 128, 128, 128, 128]  // los 6 rasgos
        let flags: UInt8 = 3  // dormido y soñando
        let comp: [UInt8] = Array("jugar".utf8)
        let vis: [UInt8] = Array("contento".utf8)
        let cand: [UInt8] = Array("dorm".utf8)
        b.append(contentsOf: estados)
        b.append(contentsOf: rasgos)
        b.append(flags)
        b.append(UInt8(comp.count)); b.append(contentsOf: comp)
        b.append(UInt8(vis.count)); b.append(contentsOf: vis)
        b.append(1); b.append(UInt8(cand.count)); b.append(contentsOf: cand); b.append(75)
        b.append(60)
        let v = try XCTUnwrap(leerVida(b))
        XCTAssertEqual(v.estado["energia"] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(v.estado["aburrimiento"] ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(v.estado["estres"] ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(v.dormido)
        XCTAssertTrue(v.sonando)
        XCTAssertFalse(v.superposicion)
        XCTAssertEqual(v.comportamiento, "jugar")
        XCTAssertEqual(v.visible, "contento")
        XCTAssertEqual(v.candidatos.first?.nombre, "dorm")
        XCTAssertEqual(v.candidatos.first?.puntaje ?? 0, 0.75, accuracy: 0.001)
        XCTAssertNil(leerVida([0x9B, 1]))
        XCTAssertNil(leerVida([0x9E, 0, 0]))
    }

    func testMemoria() {
        var horas = Array(repeating: 0, count: 24)
        horas[8] = 2
        horas[19] = 7
        horas[21] = 4
        let o: [String: Any] = ["dias": 12, "racha": 3, "caricias": 140, "toques": 9, "horas": horas,
                                "gustos": ["caricia": 3, "musica": 1, "tacto": -2, "voz": 5, "nombre": 2],
                                "hitos": ["primer-dia", "siete-dias"], "deriva": ["picardia": 0.1]]
        let m = Memoria(o)
        XCTAssertEqual(m.dias, 12)
        XCTAssertEqual(m.caricias, 140)
        XCTAssertEqual(m.horaPreferida, 19)
        XCTAssertEqual(m.mejoresGustos, ["voz", "caricia", "nombre"])
        XCTAssertEqual(m.hitos.count, 2)
        XCTAssertNil(Memoria().horaPreferida)  // nunca aparece 3 veces a la misma hora
    }

    func testAutoresYEstados() {
        XCTAssertEqual(VersionConfig(version: 3, autor: "mcp:Claude", creada: nil).nombreAutor, "IA · Claude")
        XCTAssertEqual(VersionConfig(version: 2, autor: "app", creada: nil).nombreAutor, "App")
        XCTAssertEqual(VersionConfig(version: 1, autor: "bicho", creada: nil).nombreAutor, "En el robot")
        XCTAssertEqual(Actualizacion(["id": 1, "version": "1.4.0", "estado": "descargando", "progreso": 40]).nombreEstado, "Bajando")
        XCTAssertEqual(Actualizacion(["estado": "confirmada"]).nombreEstado, "Lista")
    }

    func testComandoClaude() {
        XCTAssertEqual(comandoClaude(url: "https://api.x/mcp", token: "abc"),
                       #"claude mcp add --transport http sintetica https://api.x/mcp --header "Authorization: Bearer abc""#)
    }

    func testDibujosYAnimacionesDeFabrica() {
        XCTAssertEqual(VidaBase.dibujos.count, 16)
        XCTAssertEqual(VidaBase.dibujos.first?.nombre, "neutral")
        XCTAssertNotNil(VidaBase.dibujos.first?.doc["formas"])
        XCTAssertNil(VidaBase.dibujos.first?.doc["numero"])
        XCTAssertEqual(VidaBase.animaciones.map(\.nombre), ["chispas", "latido", "mareo"])
        // Un dibujo del manual copiado como propio y una animación de ejemplo: el núcleo los acepta.
        var c = ConfigDoc()
        if let d = VidaBase.dibujos.first(where: { $0.nombre == "contento" }) { c.ponerExpresion("mi-contento", d.doc) }
        if let a = VidaBase.animaciones.first { c.raiz["animaciones"] = [a.nombre: a.doc] }
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testNavegacion() {
        var r: [Ruta] = [.robot("A1B2C3D4E5F6")]
        XCTAssertTrue(Navegacion.volver(&r))
        XCTAssertEqual(r, [])
        XCTAssertFalse(Navegacion.volver(&r))  // ya en Mis robots
        r = [.escanear, .vinculando(DatosQr(id: "A1B2C3D4E5F6", codigo: "K7Q2XM"))]
        Navegacion.volver(&r)
        XCTAssertEqual(r, [.escanear])
        r.append(.cuenta)
        Navegacion.alInicio(&r)
        XCTAssertTrue(r.isEmpty)
    }
}

@MainActor
final class CarasDeImagenTests: XCTestCase {
    /// Un círculo opaco de 40 × 40 en el medio de un lienzo transparente de 100 × 60.
    private func dibujo() -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 60), format: f).image { ctx in
            UIColor.orange.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 30, y: 10, width: 40, height: 40))
        }
    }

    func testQoiConTransparencia() {
        var rgba = [UInt8](repeating: 0, count: 6 * 4 * 4)
        for i in 0 ..< 24 { rgba[i * 4] = UInt8(i * 10); rgba[i * 4 + 1] = 200; rgba[i * 4 + 2] = 3; rgba[i * 4 + 3] = i % 3 == 0 ? 0 : 255 }
        for i in 0 ..< 24 where rgba[i * 4 + 3] == 0 { rgba[i * 4] = 0; rgba[i * 4 + 1] = 0; rgba[i * 4 + 2] = 0 }
        let q = Qoi.codificarRGBA(rgba, ancho: 6, alto: 4)
        XCTAssertEqual(q[12], 4)
        let d = Qoi.decodificarRGBA(q)
        XCTAssertEqual(d?.canales, 4)
        XCTAssertEqual(d?.rgba, rgba)
    }

    func testPrepararSpriteRecorta() throws {
        let q = try XCTUnwrap(PrepararSprite.qoi(dibujo()))
        let d = try XCTUnwrap(Qoi.decodificarRGBA(q))
        XCTAssertEqual(d.canales, 4)
        XCTAssertLessThanOrEqual(abs(d.ancho - 40), 2)  // recortado a lo que se ve
        XCTAssertLessThanOrEqual(abs(d.alto - 40), 2)
        XCTAssertEqual(d.rgba[3], 0)  // la esquina es transparente
        // Y el núcleo lo acepta como sprite y dibuja una cara de imagen con él.
        XCTAssertTrue(Nucleo.spriteSuelto(0, q))
        var c = ConfigDoc()
        c.ponerExpresion("mi-imagen", ["sprites": ["ojo": 0], "tamano": 0.4])
        XCTAssertNil(Nucleo.validar(c.texto))
        XCTAssertNotNil(Nucleo.dibujarExpresion(config: c.texto, nombre: "mi-imagen", ancho: 160, alto: 86, redonda: false, t: 0.4, cierre: 1))
        Nucleo.spriteSuelto(0, [])
    }

    func testSpritesEnLaConfig() {
        var c = ConfigDoc()
        c.ponerExpresion("a", ["sprites": ["ojo": 0, "boca": 2]])
        c.ponerExpresion("b", ["sprites": ["ojo": 1]])
        c.ponerExpresion("contento", ["ojo": ["w": 0.1]])
        XCTAssertEqual(c.deImagen, ["a", "b"])
        XCTAssertEqual(c.sprite("a", "boca"), 2)
        XCTAssertNil(c.sprite("a", "ojo_cerrado"))
        XCTAssertEqual(c.spritesEnUso(), [0, 1, 2])
        XCTAssertEqual(c.spritesEnUso(menos: "a"), [1])
        XCTAssertEqual(spriteLibre(usados: c.spritesEnUso()), 3)
        XCTAssertNil(spriteLibre(usados: Set(0 ..< 12)))
        c.ponerCaraSiempre("a")
        XCTAssertEqual(c.caraSiempre, "a")
        c.ponerCaraSiempre("")
        XCTAssertNil(c.raiz["cara"])
        XCTAssertTrue(esImagen(["sprites": ["ojo": 0]]))
        XCTAssertFalse(esImagen(["formas": []]))
    }

    func testListaDeSprites() {
        // [0xA6][0][máscara u16] y por cada uno [espacio][u32 largo][u32 CRC].
        let b: [UInt8] = [0xA6, 0, 0x05, 0, 8, 10, 0, 0, 0, 1, 2, 3, 4, 10, 20, 0, 0, 0, 0xFF, 0, 0, 0]
        let l = leerListaSprites(b)
        XCTAssertEqual(l.map(\.espacio), [0, 2])
        XCTAssertEqual(l.first?.largo, 10)
        XCTAssertEqual(l.first?.crc, 0x0403_0201)
        XCTAssertEqual(leerListaSprites([0xA6, 0x08]), [])  // un firmware anterior
        XCTAssertEqual(ComandoImagen.listarSprites(), [0x26])
    }
}

/// El paquete de vida (protocolo v1.6 y v1.7) contra shared/protocolo/vectores.json.
@MainActor
final class PaqueteDeVidaTests: XCTestCase {
    private func vector(_ nombre: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vectores", withExtension: "json"))
        let v = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let l = v["comandos"] as? [[String: Any]] ?? []
        return try XCTUnwrap(l.first { $0["nombre"] as? String == nombre }, nombre)
    }

    func testComandosContraLosVectores() throws {
        let d = try vector("decir hola")
        XCTAssertEqual(hex(Comando.decir(d["texto"] as! String)), d["hex"] as? String)
        let e = try vector("decir con expresion")
        XCTAssertEqual(hex(Comando.decir(e["texto"] as! String, expresion: e["expresion"] as! String)), e["hex"] as? String)
        let c = try vector("clima")
        let clima = Comando.clima(temp: (c["temp"] as! NSNumber).doubleValue, codigo: c["codigo"] as! Int, max: c["max"] as! Int,
                                  min: c["min"] as! Int, dia: c["dia"] as! Bool, ciudad: c["ciudad"] as! String)
        XCTAssertEqual(hex(clima), c["hex"] as? String)
        XCTAssertEqual(hex(Comando.alarma("probar")), try vector("alarma probar")["hex"] as? String)
        XCTAssertEqual(hex(Comando.alarma("posponer")), try vector("alarma posponer")["hex"] as? String)
        XCTAssertEqual(hex(Comando.jugar("dado")), try vector("jugar dado")["hex"] as? String)
        XCTAssertEqual(hex(Comando.jugar("terminar")), try vector("jugar terminar")["hex"] as? String)
        let a = try vector("aviso whatsapp")
        XCTAssertEqual(hex(Comando.aviso(llamada: a["tipo"] as? String == "llamada", app: a["app"] as! String, contacto: a["contacto"] as! String)),
                       a["hex"] as? String)
        XCTAssertEqual(hex(Comando.animo("medio")), try vector("animo medio")["hex"] as? String)
        let m = try vector("mirar derecha")
        XCTAssertEqual(hex(Comando.mirar(x: (m["x"] as! NSNumber).doubleValue, y: (m["y"] as! NSNumber).doubleValue)), m["hex"] as? String)
    }

    func testCortesDeLosComandos() {
        // El globo es de 60 bytes como mucho, sin partir una letra.
        let largo = String(repeating: "ñ", count: 40)  // 80 bytes
        let b = Comando.decir(largo)
        XCTAssertEqual(b.count, 2 + 60)
        XCTAssertEqual(Comando.aviso(llamada: true, app: String(repeating: "a", count: 30), contacto: "")[1], 1)
        XCTAssertEqual(Comando.aviso(llamada: false, app: String(repeating: "a", count: 30), contacto: "")[2], 24)
        XCTAssertEqual(Comando.mirar(x: 2, y: -2), [0x46, 100, 156])  // -100 = 0x9c
        XCTAssertEqual(EVENTOS.firstIndex(of: "despertador"), 33)
        XCTAssertEqual(EVENTOS.firstIndex(of: "juego"), 34)
        XCTAssertEqual(EVENTOS.firstIndex(of: "animo"), 35)
    }

    func testAvisosNuevos() {
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9E, 0, 1, 0, 0, 0, 0, 0, 0x21]), [.despertador])
        // Juego: dado (3) ganado por el dueño (1) = 3·16 + 1.
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9E, 0, 2, 0, 0, 0, 0, 0, 0x22, 0, 0, 0, 0, 5, 0x31]), [.juego(3, 1)])
        XCTAssertEqual(avisosDeMarco(car: 2, [0x9E, 0, 2, 0, 0, 0, 0, 0, 0x23, 0, 0, 0, 0, 6, 2]), [.animo(2)])
    }

    func testDespertador() {
        var c = ConfigDoc()
        XCTAssertNil(c.despertador)
        XCTAssertFalse(c.despertadorVisible.activo)
        c.cambiarDespertador { $0.hora = sumarMinutos($0.hora, 60) }
        let d = c.despertador
        XCTAssertEqual(d?.hora, "08:30")
        XCTAssertEqual(d?.dias, "LMXJV")
        XCTAssertEqual(d?.activo, true)
        c.cambiarDespertador { $0.alternar("S"); $0.alternar("D") }
        XCTAssertNil((c.raiz["despertador"] as? [String: Any])?["dias"])  // los 7 = todos
        c.cambiarDespertador { $0.texto = "¡Arriba!" }
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testCuidado() {
        var c = ConfigDoc()
        XCTAssertEqual(c.cuidado, Cuidado())
        c.cambiarCuidado { $0.ponerPausa(10) }
        XCTAssertEqual(c.cuidado.pausa, 30)  // de "no" salta a 30
        c.cambiarCuidado { $0.ponerPausa(0); $0.agua = 2; $0.moverTrabajo(desde: true, -30); $0.alternarDia("V") }
        XCTAssertEqual(c.cuidado.pausa, 0)
        XCTAssertEqual(c.cuidado.desde, "08:30")
        XCTAssertEqual(c.cuidado.diasTrabajo, "LMXJ")
        XCTAssertNil(Nucleo.validar(c.texto))
    }

    func testAvisosDelCeluYHabla() {
        var c = ConfigDoc()
        var a = AvisoCelu(tipo: "llamada", expresion: "sorpresa", decir: "{contacto}")
        a.app = "WhatsApp"
        a.sonido = false
        c.avisos = [a, AvisoCelu()]
        let o = c.raiz["avisos"] as? [[String: Any]] ?? []
        XCTAssertEqual(o.count, 2)
        XCTAssertEqual(o[0]["sonido"] as? Bool, false)
        XCTAssertNil(o[1]["sonido"])  // suena: no se escribe
        XCTAssertNil(o[1]["app"])
        XCTAssertEqual(c.avisos.first?.app, "WhatsApp")
        c.ponerFrecuenciaHabla(0.8)
        c.ponerFrases("despertar", ["¡Arriba, {dueno}!"])
        XCTAssertEqual(c.totalFrases, 1)
        XCTAssertEqual(c.frasesPropias["despertar"], ["¡Arriba, {dueno}!"])
        XCTAssertNil(Nucleo.validar(c.texto))
        c.ponerFrases("despertar", [])
        XCTAssertNil((c.raiz["habla"] as? [String: Any])?["propias"])
        XCTAssertEqual(armarFrase("¡Arriba,   {dueno}!", dueno: "Nahuel", robot: "Toto"), "¡Arriba, Nahuel!")
        XCTAssertEqual(armarFrase("Soy {robot}", dueno: "", robot: "Toto"), "Soy Toto")
    }

    func testUbicacionYResumen() {
        var c = ConfigDoc()
        c.ponerUbicacion(Ubicacion(lat: -34.603722, lon: -58.381592, ciudad: "Buenos Aires, Argentina"))
        XCTAssertEqual(c.ubicacion?.lat ?? 0, -34.6037, accuracy: 0.00001)
        XCTAssertEqual(c.ubicacion?.ciudad, "Buenos Aires, Argentina")
        XCTAssertNil(Nucleo.validar(c.texto))
        let r = ResumenDia(["juegos": 3, "ganados": 1, "sonoCon": ["oveja"], "animo": 2, "espero": 19])
        XCTAssertEqual(r.animo, "medio")
        XCTAssertEqual(r.espero, "19:00")
        XCTAssertEqual(ResumenDia(["animo": "Más o menos"]).animo, "medio")
        XCTAssertEqual(ResumenDia(["animo": "mal"]).animo, "mal")
        let m = Memoria(["juegosJugados": 30, "juegosGanados": 12, "mejorReflejo": 245, "juegosHoy": 3])
        XCTAssertEqual(m.juegosJugados, 30)
        XCTAssertEqual(m.mejorReflejo, 245)
        let l = Lugar(nombre: "Rosario", region: "Santa Fe", pais: "Argentina", lat: 0, lon: 0, ciudad: "Rosario")
        XCTAssertEqual(l.detalle, "Santa Fe · Argentina")
    }
}

/// Las automatizaciones nuevas (a una hora, decir, cara, modo, despertar), como la web.
@MainActor
final class AutomatizacionesNuevasTests: XCTestCase {
    func testAUnaHora() throws {
        var a = Automatizacion.nueva(ahora: Date(timeIntervalSince1970: 1_793_000_000))
        a.ponerCuando("hora")
        XCTAssertEqual(a.hora, "08:00")
        XCTAssertNil(a.dias)
        a.alternarDia("S")
        a.alternarDia("D")
        XCTAssertEqual(a.dias, "LMXJV")
        a.alternarDia("S"); a.alternarDia("D")
        XCTAssertNil(a.dias)  // los 7 = todos
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        XCTAssertEqual(o["hora"] as? String, "08:00")
        XCTAssertNil(o["dias"])
        a.ponerCuando("expresion")
        XCTAssertNil(a.hora)
        XCTAssertNil(a.dias)
    }

    func testAccionesNuevas() throws {
        XCTAssertEqual(AccionAuto.nueva("decir", otro: nil), AccionAuto(tipo: "decir", texto: "Buen día, {dueno}: {clima}"))
        XCTAssertEqual(AccionAuto.nueva("cara", otro: nil), AccionAuto(tipo: "cara", expresion: "contento"))
        XCTAssertEqual(AccionAuto.nueva("modo", otro: nil), AccionAuto(tipo: "modo", modo: "reloj"))
        let d = AccionAuto.nueva("despertar", otro: nil)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        XCTAssertEqual(Set(o.keys), ["tipo"])
        XCTAssertEqual(ACCIONES_AUTO.map(\.tipo), ["decir", "cara", "modo", "despertar", "telegram", "webhook", "robot"])
        XCTAssertTrue(PLANTILLAS_AUTO.contains("{clima}"))
        XCTAssertTrue(PLANTILLAS_AUTO.contains("{dueno}"))
    }

    func testCuandos() {
        XCTAssertEqual(Automatizacion.cuandos(["recordatorio", "despertador", "juego"]), ["hora", "despertador", "recordatorio", "juego"])
        for k in ["hora", "despertador", "juego", "animo", "bicho-cerca"] { XCTAssertNotNil(NOMBRES_CUANDO[k], k) }
        let json = #"{"automatizaciones":[{"id":"h","activa":true,"cuando":"hora","hora":"07:15","dias":"LMXJV","hacer":[{"tipo":"modo","modo":"clima"},{"tipo":"despertar"}]}]}"#
        let r = ApiSintetica.leerAutomatizaciones(Data(json.utf8))
        XCTAssertEqual(r.lista.first?.hora, "07:15")
        XCTAssertEqual(r.lista.first?.dias, "LMXJV")
        XCTAssertEqual(r.lista.first?.hacer.first?.modo, "clima")
        XCTAssertEqual(r.lista.first?.hacer.last?.tipo, "despertar")
    }

    func testSituacionesAgrupadas() {
        let enGrupos = GRUPOS_SITUACION.flatMap(\.situaciones)
        XCTAssertEqual(Set(enGrupos), Set(SITUACIONES))
        XCTAssertEqual(enGrupos.count, Set(enGrupos).count)  // ninguna repetida
        XCTAssertEqual(armarFrase("Hola {dueno}, {clima}", dueno: "Nahuel", robot: "Toto"), "Hola Nahuel,")
    }
}
