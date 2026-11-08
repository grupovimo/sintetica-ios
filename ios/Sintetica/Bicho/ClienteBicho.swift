import Foundation
import Observation

enum ErrorBicho: LocalizedError {
    case rechazo(String)
    case tiempo
    var errorDescription: String? {
        switch self {
        case let .rechazo(m): m
        case .tiempo: "El bicho no contestó a tiempo."
        }
    }
}

/// Corre `operacion` con un límite de tiempo.
@MainActor
func conTiempo<T: Sendable>(_ segundos: Double, _ operacion: @escaping @MainActor () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await operacion() }
        g.addTask { try await Task.sleep(for: .seconds(segundos)); throw ErrorBicho.tiempo }
        let r = try await g.next()!
        g.cancelAll()
        return r
    }
}

/// Habla con un bicho por un transporte: comandos, estado y configuración.
@MainActor
@Observable
final class ClienteBicho {
    private(set) var estado: Estado?
    @ObservationIgnored let transporte: Transporte
    @ObservationIgnored private var escucha: Task<Void, Never>?

    init(_ transporte: Transporte) {
        self.transporte = transporte
        let flujo = transporte.difusor.escuchar()
        escucha = Task { [weak self] in
            for await (car, b) in flujo where car == .estado {
                if let e = try? leerEstado(b) { self?.estado = e }
            }
        }
    }

    func conectar() async throws {
        try await transporte.conectar()
        try await actualizarEstado()
    }

    @discardableResult
    func actualizarEstado() async throws -> Estado {
        let e = try leerEstado(try await transporte.leerEstado())
        estado = e
        return e
    }

    /// Escribe y espera la respuesta a esa misma operación.
    private func pedir(_ car: Car, _ datos: [UInt8], plazo: Double = 5) async throws -> Respuesta {
        let op = datos[0] & 0x7F
        let flujo = transporte.difusor.escuchar()
        try await transporte.escribir(car, datos)
        return try await conTiempo(plazo) {
            for await (c, b) in flujo where c == car {
                let r = leerRespuesta(b)
                if r.op == op { return r }
            }
            throw ErrorBicho.tiempo
        }
    }

    @discardableResult
    private func exigir(_ car: Car, _ datos: [UInt8]) async throws -> Respuesta {
        let r = try await pedir(car, datos)
        guard r.ok else { throw ErrorBicho.rechazo(r.mensaje) }
        return r
    }

    /// Vincula con el código del QR y devuelve la clave que hay que guardar.
    func vincular(_ codigo: String) async throws -> [UInt8] {
        let r = try await exigir(.comando, Comando.vincular(codigo))
        await mandarHora()
        try await actualizarEstado()
        guard case let .resultado(_, _, _, clave?) = r else { throw ErrorBicho.rechazo("El bicho no mandó la clave.") }
        return clave
    }

    func autenticar(_ clave: [UInt8]) async throws {
        try await exigir(.comando, Comando.autenticar(clave))
        await mandarHora()
        try await actualizarEstado()
    }

    /// Le pasa la hora del celu (el broche no tiene WiFi: es la única forma de saberla).
    /// Un firmware anterior a la v1.4 no lo entiende: no pasa nada.
    private func mandarHora() async {
        let ahora = Date()
        let zona = TimeZone.current.secondsFromGMT(for: ahora) / 60
        _ = try? await exigir(.comando, Comando.hora(epochUtc: UInt32(ahora.timeIntervalSince1970), zonaMinutos: zona))
    }

    func probarComportamiento(_ nombre: String) async throws { try await exigir(.comando, Comando.comportamiento(nombre)) }

    func fijarExpresion(_ nombre: String?) async throws { try await exigir(.comando, Comando.expresion(nombre ?? "")); try await actualizarEstado() }
    func cambiarNombre(_ nombre: String) async throws { try await exigir(.comando, Comando.nombre(nombre)); try await actualizarEstado() }
    func evento(_ nombre: String) async throws { try await exigir(.comando, Comando.evento(nombre)) }
    func desvincular() async throws { try await exigir(.comando, Comando.desvincular()) }
    func reproducir(_ animacion: String?) async throws { try await exigir(.comando, Comando.reproducir(animacion ?? "")); try await actualizarEstado() }
    /// El WiFi del bicho (solo por BLE).
    func configurarRed(_ ssid: String, clave: String) async throws { try await exigir(.comando, Comando.red(ssid, clave: clave)); try await actualizarEstado() }
    /// Las credenciales de la nube que dio la API al sumarlo a la cuenta (solo por BLE).
    func configurarNube(url: String, usuario: String, clave: String) async throws {
        try await exigir(.comando, Comando.nube(url: url, usuario: usuario, clave: clave))
    }
    func olvidarRed() async throws { try await exigir(.comando, Comando.olvidarRed()); try await actualizarEstado() }

    /// Instala un firmware firmado por BLE (el manifiesto lo da la API). El bicho
    /// verifica la firma, borra la otra partición (unos segundos), recibe los
    /// bloques, verifica el SHA-256 y reinicia.
    func instalarFirmware(manifiesto: [UInt8], binario: [UInt8], progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let ini = try await pedir(.ota, [Op.otaInicio] + manifiesto, plazo: 60)
        guard ini.ok else { throw ErrorBicho.rechazo("El bicho no aceptó el firmware: \(ini.mensaje)") }
        // Si un bloque falla, el bicho avisa con [0xB1][código] y aborta.
        let flujo = transporte.difusor.escuchar()
        let falla = FallaOta()
        let vigia = Task { @MainActor in
            for await (c, b) in flujo where c == .ota {
                let r = leerRespuesta(b)
                if r.op == Op.otaBloque, !r.ok { falla.mensaje = r.mensaje; return }
            }
        }
        defer { vigia.cancel() }
        let porBloque = 175
        var off = 0
        while off < binario.count {
            if let m = falla.mensaje { throw ErrorBicho.rechazo("Se cortó la actualización: \(m)") }
            let fin = min(binario.count, off + porBloque)
            let o = UInt32(off)
            let b: [UInt8] = [Op.otaBloque, UInt8(o & 0xFF), UInt8(o >> 8 & 0xFF), UInt8(o >> 16 & 0xFF), UInt8(o >> 24 & 0xFF)] + Array(binario[off ..< fin])
            try await transporte.escribir(.ota, b)
            off = fin
            progreso(Double(off) / Double(binario.count))
        }
        let r = try await pedir(.ota, [Op.otaFin], plazo: 60)
        guard r.ok else { throw ErrorBicho.rechazo("El bicho no instaló el firmware: \(r.mensaje)") }
    }

    /// Pide la configuración completa (JSON).
    func pedirConfig() async throws -> String {
        let flujo = transporte.difusor.escuchar()
        try await transporte.escribir(.config, Comando.pedirConfig())
        return try await conTiempo(10) {
            var armador = ArmadorDeConfig()
            for await (c, b) in flujo where c == .config {
                let r = leerRespuesta(b)
                if !r.ok { throw ErrorBicho.rechazo(r.mensaje) }
                if let texto = try armador.agregar(r) { return texto }
            }
            throw ErrorBicho.tiempo
        }
    }

    /// Manda una configuración entera; si el bicho la rechaza, explica por qué.
    func mandarConfig(_ json: String) async throws {
        let flujo = transporte.difusor.escuchar()
        for e in escriturasDeConfig(json) { try await transporte.escribir(.config, e) }
        let r: Respuesta = try await conTiempo(10) {
            for await (c, b) in flujo where c == .config {
                let r = leerRespuesta(b)
                if r.op == Op.configFin || !r.ok { return r }
            }
            throw ErrorBicho.tiempo
        }
        guard r.ok else { throw ErrorBicho.rechazo("El bicho no aceptó la configuración: \(r.mensaje)") }
        try await actualizarEstado()
    }

    /// Manda una imagen QOI (del tamaño de la pantalla) a un espacio, avisando el progreso (0 a 1).
    func subirImagen(_ espacio: Int, _ qoi: [UInt8], progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let flujo = transporte.difusor.escuchar()
        let escrituras = escriturasDeImagen(espacio, qoi)
        for (i, e) in escrituras.enumerated() {
            try await transporte.escribir(.imagen, e)
            progreso(Double(i + 1) / Double(escrituras.count))
        }
        let r: Respuesta = try await conTiempo(15) {
            for await (c, b) in flujo where c == .imagen {
                let r = leerRespuesta(b)
                if r.op == Op.imgFin || (r.op != Op.imgListar && !r.ok) { return r }
            }
            throw ErrorBicho.tiempo
        }
        guard r.ok else { throw ErrorBicho.rechazo("El bicho no aceptó la imagen: \(r.mensaje)") }
    }

    func borrarImagen(_ espacio: Int) async throws { try await exigir(.imagen, ComandoImagen.borrar(espacio)) }

    func listarImagenes() async throws -> [EspacioImagen] {
        let flujo = transporte.difusor.escuchar()
        try await transporte.escribir(.imagen, ComandoImagen.listar())
        return try await conTiempo(5) {
            for await (c, b) in flujo where c == .imagen && b.first == (Op.imgListar | Op.respuesta) {
                guard b.count > 1, b[1] == 0 else { throw ErrorBicho.rechazo(leerRespuesta(b).mensaje) }
                return leerListaImagenes(b)
            }
            throw ErrorBicho.tiempo
        }
    }

    /// Los sprites de las caras de imagen (v1.5); un firmware anterior no tiene.
    func listarSprites() async throws -> [EspacioImagen] {
        let flujo = transporte.difusor.escuchar()
        try await transporte.escribir(.imagen, ComandoImagen.listarSprites())
        return try await conTiempo(5) {
            for await (c, b) in flujo where c == .imagen && b.first == (Op.sprListar | Op.respuesta) {
                return leerListaSprites(b)
            }
            throw ErrorBicho.tiempo
        }
    }

    func cerrar() {
        escucha?.cancel()
        transporte.cerrar()
    }
}

/// Lo que avisó el bicho si un bloque de la OTA falló.
@MainActor
private final class FallaOta { var mensaje: String? }
