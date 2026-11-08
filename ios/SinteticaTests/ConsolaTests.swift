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
        XCTAssertEqual(u.encuadre.foto.ancho, 155.56, accuracy: 0.001)
        XCTAssertEqual(u.encuadre.pantalla.alto, 42.78, accuracy: 0.001)
        XCTAssertTrue(u.encuadre.apaisada(redonda: u.redonda))  // se agranda al 185 %
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
        b += [255, 128, 0, 51, 0, 0, 255]  // los 7 estados
        b += [128, 128, 128, 128, 128, 128]  // los 6 rasgos
        b += [1 | 2]  // dormido y soñando
        b += [5] + Array("jugar".utf8)
        b += [8] + Array("contento".utf8)
        b += [1, 4] + Array("dormir".utf8.prefix(4)) + [75]
        b += [60]
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
