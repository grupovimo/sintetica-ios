import Foundation
import Observation
import UIKit

/// Un robot abierto en la consola: su estado en vivo, su config y sus
/// imágenes. Habla por la nube si está en la cuenta (la config manda la nube:
/// si no, la sincronización pisaría lo cambiado por BLE), por BLE si solo está
/// vinculado a este celu, o con el núcleo del celu ("probar sin robot").
/// Como web/src/lib/bicho.svelte.ts y web/src/lib/consola/guardado.svelte.ts.
@MainActor
@Observable
final class ModeloRobot {
    enum Fase: Equatable { case conectando, lista, error(String, revincular: Bool) }
    enum Via: Equatable { case demo, ble, nube }
    enum Guardado: Equatable { case listo, guardando, guardado, error }
    struct Aviso: Equatable { let texto: String; let icono: String; let cuando: Date; var despertador = false }
    enum Fuente { case datos(Data), video(URL) }

    let id: String
    private(set) var via: Via = .nube
    var fase: Fase = .conectando
    var robot: RobotNube?
    var estado: Estado?
    var config = ConfigDoc()
    private(set) var versionConfig = 0
    var espacios: [EspacioImagen] = []
    var miniaturas: [Int: [UIImage]] = [:]
    var duraciones: [Int: [Int]] = [:]
    var subiendo = -1
    var progreso: Double?
    var errorImagenes = ""
    var aviso: Aviso?
    /// Los sprites de las caras de imagen (QOI, por número 0 a 11) y su miniatura.
    var sprites: [Int: [UInt8]] = [:]
    var miniSprites: [Int: UIImage] = [:]
    /// Lo que suena (Spotify o el celu).
    var suena: Suena?
    var vida: VidaEnVivo?
    var vidaEn = Date.distantPast
    var ota: Actualizacion?
    var guardado: Guardado = .listo
    var errorGuardado = ""
    private(set) var cliente: ClienteBicho?

    @ObservationIgnored private var pendiente: ConfigDoc?
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored private var escucha: Task<Void, Never>?
    @ObservationIgnored private var espejo: Task<Void, Never>?
    @ObservationIgnored private var oyente: UUID?
    @ObservationIgnored private var crcCargado: [Int: UInt32] = [:]
    @ObservationIgnored private var crcSprites: [Int: UInt32] = [:]
    @ObservationIgnored private var ultimaFijada = ""
    @ObservationIgnored var pausaEspejo = Date.distantPast
    @ObservationIgnored private let conexion = UUID().uuidString
    /// El núcleo guarda al anfitrión con una referencia débil: el modelo lo mantiene vivo.
    @ObservationIgnored private let anfitrion = AnfitrionEnMemoria()

    init(id: String) {
        self.id = id
        if id.hasPrefix(ID_DEMO) { via = .demo }
    }

    private var api: ApiSintetica { Cuenta.compartida.api }
    var esDemo: Bool { via == .demo }
    var esNube: Bool { via == .nube }
    var esBle: Bool { via == .ble }
    var vinculado: Bool { Vinculados.compartidos.buscar(id) != nil }

    var perfil: String {
        if let p = robot?.perfil, !p.isEmpty { return p }
        if let p = estado?.perfil, !p.isEmpty { return p }
        return id == ID_DEMO_BROCHE ? "broche" : ""
    }

    var pantalla: Pantalla { pantallaDe(perfil: perfil, estado: estado) }
    var producto: ModeloProducto { ModeloProducto.de(perfil: perfil, virtual: robot?.virtual ?? esDemo, pantalla: pantalla) }
    var conectado: Bool { esNube ? (robot?.conectado ?? false) : fase == .lista }

    var nombre: String {
        if let a = robot?.apodo, !a.isEmpty { return a }
        if let n = config.nombre, !n.isEmpty { return n }
        if let n = estado?.nombre, !n.isEmpty, n != "bicho" { return n }
        return "Tu robot"
    }

    var textoGuardado: String {
        switch guardado {
        case .listo: "Al día"
        case .guardando: "Guardando…"
        case .guardado: conectado || !esNube ? "Guardado y enviado" : "Guardado · le llega al volver"
        case .error: "No se guardó"
        }
    }

    /// Tiene una cara fijada de verdad (no un recordatorio, el reloj, una imagen…).
    var caraFija: Bool { estado?.fija == true && esCara(estado?.expresion ?? "") }

    // MARK: - Abrir y cerrar

    func abrir() async {
        fase = .conectando
        cerrarConexiones()
        do {
            if esDemo {
                try await abrirDemo()
            } else if Cuenta.compartida.activa, let r = try? await api.robot(id) {
                via = .nube
                try await abrirNube(r)
            } else if vinculado {
                via = .ble
                try await abrirBle()
                if case .error = fase { return }
            } else {
                throw ErrorBicho.rechazo(Cuenta.compartida.activa ? "No está en tu cuenta." : "Entrá a tu cuenta.")
            }
            fase = .lista
            arrancarEspejo()
        } catch {
            fase = .error(error.localizedDescription, revincular: false)
        }
    }

    private func abrirDemo() async throws {
        let c = ClienteBicho(TransporteVirtual(broche: id == ID_DEMO_BROCHE))
        try await c.conectar()
        cliente = c
        estado = c.estado
        config = ConfigDoc(texto: try await c.pedirConfig())
        escuchar(c)
        await cargarImagenes()
        await cargarSprites()
    }

    private func abrirNube(_ r: RobotNube) async throws {
        robot = r
        estado = r.estado
        let c = try await api.config(id)
        versionConfig = c.version
        config = ConfigDoc(texto: c.texto)
        iniciarVistaPrevia()
        oyente = EnVivo.compartido.escuchar { [weak self] e in self?.recibir(e) }
        await cargarImagenes()
        await cargarSprites()
    }

    private func abrirBle() async throws {
        guard let v = Vinculados.compartidos.buscar(id) else { throw ErrorBicho.rechazo("No está vinculado.") }
        let p = try await Central.compartida.buscar(id: id)
        let c = ClienteBicho(TransporteBle(p))
        try await c.conectar()
        do {
            try await c.autenticar(v.clave)
        } catch {
            c.cerrar()
            fase = .error("Ya no reconoce a este celu.", revincular: true)
            return
        }
        cliente = c
        estado = c.estado
        config = ConfigDoc(texto: try await c.pedirConfig())
        iniciarVistaPrevia()
        escuchar(c)
        await cargarImagenes()
        await cargarSprites()
    }

    private func cerrarConexiones() {
        escucha?.cancel()
        espejo?.cancel()
        if let o = oyente { EnVivo.compartido.dejar(o) }
        oyente = nil
        cliente?.cerrar()
        cliente = nil
    }

    func cerrar() {
        reloj?.cancel()
        if let c = pendiente {
            pendiente = nil
            Task { _ = await self.guardarYa(c) }
        }
        cerrarConexiones()
    }

    // MARK: - En vivo

    private func escuchar(_ c: ClienteBicho) {
        let flujo = c.transporte.difusor.escuchar()
        escucha = Task { [weak self] in
            for await (car, b) in flujo {
                guard let self else { return }
                if car == .estado, let e = try? leerEstado(b) { self.estado = e }
                self.recibirMarco(car.rawValue, b)
            }
        }
    }

    private func recibir(_ e: EventoNube) {
        // Lo que suena puede ser de la cuenta (Spotify, sin robot) o de este robot.
        if e.tipo == "musica", e.bicho.isEmpty || e.bicho == id, let t = e.datos["titulo"] as? String {
            suena = (e.datos["sonando"] as? Bool ?? false) ? Suena(sonando: true, titulo: t, artista: e.datos["artista"] as? String ?? "") : nil
            return
        }
        guard e.bicho == id else { return }
        switch e.tipo {
        case "estado":
            if let x = estadoDeJSON(e.datos) { estado = x; robot?.estado = x }
        case "conexion":
            robot?.conectado = e.datos["conectado"] as? Bool ?? false
        case "config":
            let v = (e.datos["version"] as? NSNumber)?.intValue ?? 0
            if v != versionConfig, pendiente == nil, guardado != .guardando { Task { await recargarConfig() } }
        case "imagenes":
            Task { await cargarImagenes() }
        case "sprites":
            Task { await cargarSprites() }
        case "bicho":
            if let b = e.datos["bicho"] as? [String: Any] { robot = RobotNube(b); if let x = robot?.estado { estado = x } }
        case "mcp":
            let cliente = (e.datos["cliente"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Tu IA"
            let h = (e.datos["herramienta"] as? String ?? "").replacingOccurrences(of: "_", with: " ")
            mostrarAviso("\(cliente): \(h)", icono: "sparkles", segundos: 5)
        case "marco":
            if let c = (e.datos["car"] as? NSNumber)?.intValue, let s = e.datos["datos"] as? String, let d = Data(base64Encoded: s) {
                recibirMarco(c, [UInt8](d))
            }
        case "ota":
            ota = Actualizacion(e.datos)
        case "toque":
            let t = textoToque(de: e.datos["de"] as? String ?? "", tipo: e.datos["tipo"] as? String ?? "toque", devuelto: e.datos["devuelto"] as? Bool ?? false)
            mostrarAviso(t.texto, icono: t.icono, segundos: 5)
        default:
            break
        }
    }

    /// Un marco del robot: la respuesta de Vida o un aviso suyo.
    private func recibirMarco(_ car: Int, _ b: [UInt8]) {
        if car == Car.comando.rawValue, b.count >= 2, b[0] == (Op.vida | Op.respuesta), let v = leerVida(b) {
            vida = v
            vidaEn = Date()
            return
        }
        avisar(avisosDeMarco(car: car, b))
    }

    /// Pide el estado del motor de vida (y prende o apaga sus datos en la pantalla).
    func pedirVida(superposicion: Bool? = nil) async {
        let m = Comando.vida(superposicion: superposicion)
        switch via {
        case .nube:
            guard conectado, let r = try? await api.marco(id, car: Car.comando.rawValue, datos: m, conexion: conexion) else { return }
            for (c, b) in r { recibirMarco(c, b) }
        case .ble, .demo:
            try? await cliente?.transporte.escribir(.comando, m)
        }
    }

    private func avisar(_ l: [AvisoRobot]) {
        for a in l {
            switch a {
            case let .recordatorio(i):
                let r = config.recordatorios
                mostrarAviso(i < r.count ? r[i].texto : "Recordatorio", icono: "alarm.fill", segundos: 120)
            case .pomodoro:
                mostrarAviso(estado?.expresion == "pomodoro:trabajo" ? "A trabajar" : "Tanda terminada", icono: "timer", segundos: 15)
            case .despertador:
                let t = config.despertador?.texto ?? ""
                mostrarAviso(t.isEmpty ? "Suena el despertador" : t, icono: "alarm.fill", segundos: 120, despertador: true)
            case .juego, .animo, .toque, .habito, .devolvioToque:
                break
            }
        }
    }

    func mostrarAviso(_ texto: String, icono: String, segundos: Double, despertador: Bool = false) {
        let a = Aviso(texto: texto, icono: icono, cuando: Date(), despertador: despertador)
        aviso = a
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(segundos))
            if self?.aviso == a { self?.aviso = nil }
        }
    }

    // MARK: - La vista previa (el mismo núcleo, en el celu)

    private func iniciarVistaPrevia() {
        let p = pantalla
        let ident = id.count == 12 ? id : "000000000000"
        Nucleo.iniciar(ancho: p.ancho * 2, alto: p.alto * 2, identificador: ident, anfitrion: anfitrion, redonda: p.redonda)
        Nucleo.vistaPrevia()
        aplicarEnVistaPrevia(config.texto)
        ultimaFijada = ""
    }

    /// Le pasa una config al núcleo del celu (en el robot de prueba, es él mismo).
    func aplicarEnVistaPrevia(_ texto: String) {
        for e in escriturasDeConfig(texto, tamanoBloque: 512) { Nucleo.bleEscribir(Car.config.rawValue, Data(e)) }
    }

    /// La vista previa copia la cara que muestra el robot de verdad.
    private func arrancarEspejo() {
        guard !esDemo else { return }
        espejo = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date() > self.pausaEspejo, let e = self.estado?.expresion, !e.isEmpty, esCara(e), e != self.ultimaFijada {
                    self.ultimaFijada = e
                    Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion(e)))
                } else if let e = self.estado?.expresion, !esCara(e), !self.ultimaFijada.isEmpty {
                    // No es una cara: se suelta y la vista previa lo arma sola.
                    self.ultimaFijada = ""
                    Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion("")))
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// Para probar algo en la vista previa sin que el espejo lo pise.
    func pausarEspejo(_ segundos: Double = 12) {
        pausaEspejo = Date().addingTimeInterval(segundos)
        ultimaFijada = ""
        if !esDemo { Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion(""))) }
    }

    func tocar(_ apretado: Bool) { Nucleo.tacto(apretado) }

    // MARK: - Guardar (solo, 600 ms después del último cambio)

    func cambiar(_ f: (inout ConfigDoc) -> Void) {
        var c = pendiente ?? config
        f(&c)
        c.aV2()
        pendiente = c
        config = c
        aplicarEnVistaPrevia(c.texto)
        guardado = .guardando
        errorGuardado = ""
        reloj?.cancel()
        reloj = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            await self?.mandarPendiente()
        }
    }

    private func mandarPendiente() async {
        guard let c = pendiente else { return }
        pendiente = nil
        let error = await guardarYa(c)
        if pendiente != nil { return }  // llegó otro cambio mientras guardaba: lo manda ese
        if let error {
            guardado = .error
            errorGuardado = error
            await recargarConfig()
        } else {
            guardado = .guardado
        }
    }

    /// Guarda ya una config entera (el laboratorio, el encendido): lo pendiente
    /// ya está adentro (config incluye los cambios sin mandar).
    func guardarAhora(_ c: ConfigDoc) async -> String? {
        reloj?.cancel()
        pendiente = nil
        guardado = .guardando
        let e = await guardarYa(c)
        guardado = e == nil ? .guardado : .error
        errorGuardado = e ?? ""
        if e == nil { aplicarEnVistaPrevia(config.texto) }
        return e
    }

    /// Valida con el núcleo (el mismo del robot) y la manda. Devuelve el error o nil.
    func guardarYa(_ doc: ConfigDoc) async -> String? {
        var c = doc
        c.aV2()
        let texto = c.texto
        if let e = Nucleo.validar(texto) { return e }
        do {
            switch via {
            case .nube: versionConfig = try await api.guardarConfig(id, texto)
            case .ble, .demo:
                guard let cliente else { return "Sin conexión." }
                try await cliente.mandarConfig(texto)
            }
            if pendiente == nil { config = c }
            if via == .ble, var v = Vinculados.compartidos.buscar(id), let n = c.nombre, n != v.nombre {
                v.nombre = n
                Vinculados.compartidos.guardar(v)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func recargarConfig() async {
        do {
            switch via {
            case .nube:
                let c = try await api.config(id)
                versionConfig = c.version
                config = ConfigDoc(texto: c.texto)
            case .ble, .demo:
                guard let cliente else { return }
                config = ConfigDoc(texto: try await cliente.pedirConfig())
            }
            if !esDemo { aplicarEnVistaPrevia(config.texto) }
        } catch {}
    }

    // MARK: - Comandos

    /// expresion, evento o reproducir. Devuelve el error o nil.
    @discardableResult
    func comando(_ c: [String: String]) async -> String? {
        do {
            switch via {
            case .nube: try await api.comando(id, c)
            case .ble, .demo:
                guard let cliente else { return "Sin conexión." }
                if let e = c["evento"] { try await cliente.evento(e) }
                if let x = c["expresion"] { try await cliente.fijarExpresion(x.isEmpty ? nil : x) }
                if let r = c["reproducir"] { try await cliente.reproducir(r.isEmpty ? nil : r) }
            }
            if !esNube, let e = cliente?.estado { estado = e }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Un comando del paquete de vida: por la nube con su ruta, cerca con sus bytes.
    private func mandarVida(ruta: String, cuerpo: [String: Any], bytes: [UInt8], soloMarco: Bool = false) async -> String? {
        do {
            switch via {
            case .nube:
                if soloMarco {
                    _ = try await api.marco(id, car: Car.comando.rawValue, datos: bytes, conexion: conexion)
                } else {
                    _ = try await api.pedir("/v1/bichos/\(id)/\(ruta)", "POST", cuerpo)
                }
            case .ble, .demo:
                guard let cliente else { return "Sin conexión." }
                try await cliente.comandoCrudo(bytes)
            }
            return nil
        } catch let e as ErrorApi {
            if e.estado == 409 { return "Desconectado" }
            if e.estado == 404 { return "Todavía no sabe" }
            return e.detalle.isEmpty ? e.mensaje : e.detalle
        } catch {
            return error.localizedDescription
        }
    }

    /// Que mire hacia ahí (x e y de -1 a 1): la vista previa y, si está conectado, él.
    func mirar(_ x: Double, _ y: Double) {
        let b = Comando.mirar(x: x, y: y)
        if !esDemo { Nucleo.bleEscribir(Car.comando.rawValue, Data(b)) }
        guard conectado else { return }
        Task { _ = await mandarVida(ruta: "", cuerpo: [:], bytes: b, soloMarco: true) }
    }

    /// Una cara puesta desde la conversación (nil la suelta): en la vista previa y en él.
    func caraDeConversacion(_ n: String?) {
        if !esDemo {
            pausarEspejo(n == nil ? 0 : 900)
            Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion(n ?? "")))
        }
        guard conectado else { return }
        Task { await comando(["expresion": n ?? ""]) }
    }

    /// Lo dice en un globo en su pantalla (hasta 60 bytes).
    func decir(_ texto: String, expresion: String = "") async -> String? {
        let t = cortarBytes(texto.trimmingCharacters(in: .whitespacesAndNewlines), 60)
        guard !t.isEmpty else { return nil }
        var c: [String: Any] = ["texto": t]
        if !expresion.isEmpty { c["expresion"] = expresion }
        return await mandarVida(ruta: "decir", cuerpo: c, bytes: Comando.decir(t, expresion: expresion))
    }

    /// El despertador: apagar, posponer, probar o despertar.
    func alarma(_ accion: String) async -> String? {
        await mandarVida(ruta: "alarma", cuerpo: ["accion": accion], bytes: Comando.alarma(accion))
    }

    /// Empieza un juego en su pantalla.
    func jugar(_ juego: String) async -> String? {
        await mandarVida(ruta: "jugar", cuerpo: ["juego": juego], bytes: Comando.jugar(juego))
    }

    /// Una notificación o llamada del celu (para probar los avisos).
    func avisoCelu(llamada: Bool, app: String, contacto: String) async -> String? {
        await mandarVida(ruta: "aviso", cuerpo: ["tipo": llamada ? "llamada" : "notificacion", "app": app, "contacto": contacto],
                   bytes: Comando.aviso(llamada: llamada, app: app, contacto: contacto))
    }

    /// Prueba un comportamiento en el robot.
    func probarComportamiento(_ n: String) async -> String? {
        do {
            switch via {
            case .nube: _ = try await api.marco(id, car: Car.comando.rawValue, datos: Comando.comportamiento(n), conexion: conexion)
            case .ble, .demo:
                guard let cliente else { return "Sin conexión." }
                try await cliente.probarComportamiento(n)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Imágenes

    func cargarImagenes() async {
        switch via {
        case .nube:
            guard let l = try? await api.imagenes(id) else { return }
            espacios = l.sorted { $0.espacio < $1.espacio }
            for e in espacios where crcCargado[e.espacio] != e.crc {
                guard let bytes = try? await api.imagen(id, e.espacio) else { continue }
                crcCargado[e.espacio] = e.crc
                await mostrarImagen(e.espacio, bytes, previa: nil)
            }
        case .ble, .demo:
            guard let c = cliente, let l = try? await c.listarImagenes() else { return }
            espacios = l.sorted { $0.espacio < $1.espacio }
            for e in espacios where crcCargado[e.espacio] != e.crc {
                // Otro celu la cambió: no la tenemos.
                guard let mandada = CacheImagenes.mandada(id, e.espacio), crc32(mandada) == e.crc else { continue }
                crcCargado[e.espacio] = e.crc
                await mostrarImagen(e.espacio, mandada, previa: esDemo ? nil : CacheImagenes.vistaPrevia(id, e.espacio))
            }
        }
        let hay = Set(espacios.map(\.espacio))
        for k in miniaturas.keys where !hay.contains(k) { miniaturas[k] = nil; duraciones[k] = nil; crcCargado[k] = nil }
    }

    /// La miniatura (con sus cuadros) y la copia al doble en la vista previa.
    private func mostrarImagen(_ espacio: Int, _ bytes: [UInt8], previa: [UInt8]?) async {
        let p = pantalla
        let demo = esDemo
        let r = await Task.detached(priority: .userInitiated) { () -> ([UIImage], [Int], [UInt8]?) in
            let c = PrepararImagen.cuadrosDe(bytes)
            let doble = demo ? nil : (previa ?? PrepararImagen.reescalar(bytes, ancho: p.ancho * 2, alto: p.alto * 2, redonda: p.redonda))
            return (c.map { $0.0 }, c.map { $0.1 }, doble)
        }.value
        miniaturas[espacio] = r.0
        duraciones[espacio] = r.1
        if let doble = r.2 {
            for w in escriturasDeImagen(espacio, doble, tamanoBloque: 512) { Nucleo.bleEscribir(Car.imagen.rawValue, Data(w)) }
        }
    }

    func subir(_ espacio: Int, _ fuente: Fuente) async {
        subiendo = espacio
        errorImagenes = ""
        progreso = 0
        defer { subiendo = -1; progreso = nil }
        let p = pantalla
        let demo = esDemo
        do {
            var cuadros: [(UIImage, Int)] = []
            switch fuente {
            case let .video(url): cuadros = try await PrepararImagen.cuadrosDeVideo(url, ancho: p.ancho, alto: p.alto)
            case let .datos(d):
                if PrepararImagen.esGif(d) {
                    let g = try PrepararImagen.gif(d, ancho: p.ancho, alto: p.alto, redonda: p.redonda)
                    cuadros = PrepararImagen.cuadrosDe(g.bytes)
                } else {
                    guard let img = UIImage(data: d) else { throw PrepararImagen.ErrorImagen.noEsGif }
                    cuadros = [(img, 0)]
                }
            }
            let fuentes = cuadros
            let listo = try await Task.detached(priority: .userInitiated) { () -> ([UInt8], UIImage, [UInt8]?) in
                let r = try PrepararImagen.empaquetar(fuentes, ancho: p.ancho, alto: p.alto, redonda: p.redonda)
                var doble: [UInt8]?
                if !demo { doble = try? PrepararImagen.empaquetar(fuentes, ancho: p.ancho * 2, alto: p.alto * 2, redonda: p.redonda).bytes }
                return (r.bytes, r.primero, doble)
            }.value
            switch via {
            case .nube: try await api.subirImagen(id, espacio, listo.0)
            case .ble, .demo:
                guard let c = cliente else { throw ErrorBicho.rechazo("Sin conexión.") }
                try await c.subirImagen(espacio, listo.0) { [weak self] v in self?.progreso = v }
                CacheImagenes.guardar(id, espacio, mandada: listo.0, vistaPrevia: listo.2 ?? listo.0, miniatura: listo.1)
            }
            crcCargado[espacio] = nil
            if !config.enLista(espacio) { cambiar { $0.mostrar(espacio, true) } }
            await cargarImagenes()
        } catch {
            errorImagenes = error.localizedDescription
        }
    }

    func borrar(_ espacio: Int) async {
        do {
            switch via {
            case .nube: try await api.borrarImagen(id, espacio)
            case .ble, .demo:
                try await cliente?.borrarImagen(espacio)
                CacheImagenes.borrar(id, espacio)
            }
        } catch { errorImagenes = error.localizedDescription }
        if !esDemo { Nucleo.bleEscribir(Car.imagen.rawValue, Data(ComandoImagen.borrar(espacio))) }
        if config.enLista(espacio) || config.protector == espacio {
            cambiar { c in
                c.mostrar(espacio, false)
                if c.protector == espacio { c.ponerProtector(nil) }
            }
        }
        await cargarImagenes()
    }

    // MARK: - Sprites (las caras de imagen)

    enum FuenteSprite { case datos(Data), svg(String) }

    func cargarSprites() async {
        var lista: [EspacioImagen] = []
        switch via {
        case .nube:
            guard let l = try? await api.sprites(id) else { return }
            lista = l
        case .ble, .demo:
            guard let c = cliente, let l = try? await c.listarSprites() else { return }
            lista = l
        }
        let hay = Set(lista.map(\.espacio))
        for n in Array(sprites.keys) where !hay.contains(n) {
            sprites[n] = nil
            miniSprites[n] = nil
            crcSprites[n] = nil
            Nucleo.spriteSuelto(n, [])
            if !esDemo { Nucleo.bleEscribir(Car.imagen.rawValue, Data(ComandoImagen.borrar(Op.primerSprite + n))) }
        }
        for e in lista where crcSprites[e.espacio] != e.crc {
            var bytes: [UInt8]?
            if esNube {
                bytes = try? await api.sprite(id, e.espacio)
            } else if let m = CacheImagenes.mandada(id, Op.primerSprite + e.espacio), crc32(m) == e.crc {
                bytes = m
            }
            guard let b = bytes else { continue }
            ponerSprite(e.espacio, b)
            crcSprites[e.espacio] = e.crc
        }
        Miniaturas.vaciar()
    }

    /// Lo deja en el núcleo del celu (para dibujar y para la vista previa).
    private func ponerSprite(_ n: Int, _ b: [UInt8]) {
        sprites[n] = b
        miniSprites[n] = Qoi.imagen(b).map { UIImage(cgImage: $0) }
        Nucleo.spriteSuelto(n, b)
        if !esDemo {
            for w in escriturasDeImagen(Op.primerSprite + n, b, tamanoBloque: 512) { Nucleo.bleEscribir(Car.imagen.rawValue, Data(w)) }
        }
    }

    /// Sube un dibujo como el sprite n (por la nube la API lo convierte; cerca, el celu).
    func subirSprite(_ n: Int, _ f: FuenteSprite) async throws {
        switch via {
        case .nube:
            switch f {
            case let .datos(d): try await api.subirSprite(id, n, d, tipo: "application/octet-stream")
            case let .svg(t): try await api.subirSprite(id, n, Data(t.utf8), tipo: "image/svg+xml")
            }
            crcSprites[n] = nil
            await cargarSprites()
        case .ble, .demo:
            guard case let .datos(d) = f else { throw ErrorBicho.rechazo("El SVG va por la nube.") }
            guard let img = UIImage(data: d), let q = PrepararSprite.qoi(img) else { throw PrepararImagen.ErrorImagen.noEsGif }
            guard let c = cliente else { throw ErrorBicho.rechazo("Sin conexión.") }
            try await c.subirImagen(Op.primerSprite + n, q)
            CacheImagenes.guardar(id, Op.primerSprite + n, mandada: q, vistaPrevia: q, miniatura: UIImage(data: d) ?? UIImage())
            crcSprites[n] = nil
            await cargarSprites()
        }
    }

    func borrarSprite(_ n: Int) async {
        switch via {
        case .nube: try? await api.borrarSprite(id, n)
        case .ble, .demo:
            try? await cliente?.borrarImagen(Op.primerSprite + n)
            CacheImagenes.borrar(id, Op.primerSprite + n)
        }
        await cargarSprites()
    }

    // MARK: - Ajustes

    func ponerApodo(_ n: String) async -> String? {
        let v = cortarBytes(n.trimmingCharacters(in: .whitespaces), 24)
        if esNube {
            do { robot?.apodo = try await api.ponerApodo(id, v) } catch { return error.localizedDescription }
        }
        if !v.isEmpty { cambiar { $0.nombre = v } }
        return nil
    }

    /// Lo saca de la cuenta (nube), lo desvincula (BLE) o lo reinicia (prueba).
    func quitar() async -> String? {
        do {
            switch via {
            case .nube: try await api.quitar(id)
            case .ble:
                try? await cliente?.desvincular()
                Vinculados.compartidos.olvidar(id)
            case .demo: try? await cliente?.desvincular()
            }
            cerrar()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Encender (la primera vez)

    private var claveEncendido: String { "encendido:\(id)" }
    var debeEncender: Bool {
        !UserDefaults.standard.bool(forKey: claveEncendido) && config.raiz["dueno"] == nil && !config.tienePreset
    }

    func marcarEncendido() { UserDefaults.standard.set(true, forKey: claveEncendido) }
}

/// "recordatorio:…", "pomodoro:…", "reloj:…", "imagen:…" y "protector:…" no son
/// caras: la vista previa los arma sola con la misma config y hora.
func esCara(_ e: String) -> Bool {
    !["recordatorio:", "pomodoro:", "reloj:", "imagen:", "protector:"].contains { e.hasPrefix($0) }
}

/// El aviso de un toque de un amigo (o el que te devolvió), como la web.
func textoToque(de: String, tipo: String, devuelto: Bool) -> (texto: String, icono: String) {
    let que: [String: String] = ["toque": "un toque", "abrazo": "un abrazo", "beso": "un beso", "carita": "una carita"]
    let el: [String: String] = ["toque": "el toque", "abrazo": "el abrazo", "beso": "el beso", "carita": "la carita"]
    let iconos: [String: String] = ["toque": "hand.point.right.fill", "abrazo": "figure.2.arms.open", "beso": "heart.fill", "carita": "face.smiling.inverse"]
    let texto = devuelto ? "\(de) te devolvió \(el[tipo] ?? "el toque")" : "\(de) te mandó \(que[tipo] ?? "un toque")"
    return (texto, iconos[tipo] ?? "hand.point.right.fill")
}
