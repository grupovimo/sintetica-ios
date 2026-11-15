@preconcurrency import AVFoundation
import Foundation
import Observation

/// El micrófono del celu a trozos de PCM de 16 bits, 16 kHz mono: cada trozo
/// es [u8 formato = 2][1 s de audio (32 000 bytes)], como los pide la nube.
final class MicrofonoConversacion: @unchecked Sendable {
    static let bytesPorTrozo = 32000
    private static let formatoPCM: UInt8 = 2

    private let motor = AVAudioEngine()
    private let formato16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var convertidor: AVAudioConverter?
    private let candado = NSLock()
    private var juntado = Data()
    private let alTrozo: (Data) -> Void

    init(alTrozo: @escaping (Data) -> Void) {
        self.alTrozo = alTrozo
    }

    func arrancar() throws {
        let mic = motor.inputNode
        let formato = mic.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw ErrorApi(estado: 0, mensaje: "Sin micrófono", detalle: "")
        }
        convertidor = AVAudioConverter(from: formato, to: formato16)
        mic.installTap(onBus: 0, bufferSize: 4096, format: formato) { [weak self] buf, _ in self?.convertir(buf) }
        motor.prepare()
        try motor.start()
    }

    /// Para y manda lo que quedó juntado (aunque sea menos de 1 s).
    func parar() {
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        candado.lock()
        let resto = juntado
        juntado = Data()
        candado.unlock()
        if !resto.isEmpty { alTrozo(Self.trozo(resto)) }
    }

    private static func trozo(_ pcm: Data) -> Data {
        var d = Data([formatoPCM])
        d.append(pcm)
        return d
    }

    private func convertir(_ buf: AVAudioPCMBuffer) {
        guard let c = convertidor else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: formato16, frameCapacity: cap) else { return }
        var dado = false
        var error: NSError?
        c.convert(to: out, error: &error) { _, estado in
            if dado { estado.pointee = .noDataNow; return nil }
            dado = true
            estado.pointee = .haveData
            return buf
        }
        guard error == nil, out.frameLength > 0, let p = out.int16ChannelData else { return }
        let pcm = Data(bytes: p[0], count: Int(out.frameLength) * 2)
        var listos: [Data] = []
        candado.lock()
        juntado.append(pcm)
        while juntado.count >= Self.bytesPorTrozo {
            listos.append(Self.trozo(Data(juntado.prefix(Self.bytesPorTrozo))))
            juntado = Data(juntado.dropFirst(Self.bytesPorTrozo))
        }
        candado.unlock()
        for t in listos { alTrozo(t) }
    }
}

/// Cuántos trozos llegaron y cuántos no (después de 3 intentos).
struct ResultadoSubida: Sendable {
    var subidos = 0
    var perdidos = 0
}

/// Grabar una conversación con el celu (para probar sin el broche): crea la
/// conversación en la nube, sube los trozos en orden mientras graba (de a uno,
/// cada uno hasta 3 intentos) y al parar sube lo que queda y la termina.
/// Vive en la sesión: sigue grabando aunque cambies de pantalla.
@MainActor
@Observable
final class GrabadorConversacion {
    enum Estado: Equatable { case quieto, arrancando, grabando, terminando }

    /// PCM de 16 bits ocupa 32 KB por segundo y la nube acepta hasta 64 MB.
    static let maxSegundos = 30 * 60

    private(set) var estado: Estado = .quieto
    private(set) var segundos = 0
    var aviso = ""
    /// Sube cada vez que termina una (para recargar la lista).
    private(set) var terminadas = 0

    @ObservationIgnored private var id: Int?
    @ObservationIgnored private var mic: MicrofonoConversacion?
    @ObservationIgnored private var salida: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var subida: Task<ResultadoSubida, Never>?
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored private var empezo = Date()
    @ObservationIgnored private var interrupcion: NSObjectProtocol?

    var activo: Bool { estado != .quieto }
    var grabando: Bool { estado == .grabando }

    func grabar(bicho: String = "") async {
        guard estado == .quieto else { return }
        estado = .arrancando
        aviso = ""
        guard await AVAudioApplication.requestRecordPermission() else {
            estado = .quieto
            aviso = "Sin micrófono"
            return
        }
        let api = Cuenta.compartida.api
        let c: ConversacionGrabada
        do {
            c = try await api.crearConversacion(bicho: bicho)
        } catch let e as ErrorApi {
            estado = .quieto
            aviso = e.estado == 429 ? "Por hoy, ya está" : e.mensaje
            return
        } catch {
            estado = .quieto
            aviso = "No pude"
            return
        }
        let (flujo, cont) = AsyncStream<Data>.makeStream()
        let m = MicrofonoConversacion { _ = cont.yield($0) }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try s.setActive(true)
            try m.arrancar()
        } catch {
            cont.finish()
            soltarSesion()
            try? await api.borrarConversacion(c.id)
            estado = .quieto
            aviso = "Sin micrófono"
            return
        }
        id = c.id
        mic = m
        salida = cont
        empezo = Date()
        segundos = 0
        estado = .grabando
        let cid = c.id
        subida = Task.detached { await GrabadorConversacion.subir(flujo, id: cid, api: api) }
        reloj = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.estado == .grabando else { return }
                self.segundos = Int(Date().timeIntervalSince(self.empezo))
                if self.segundos >= GrabadorConversacion.maxSegundos {
                    await self.terminar()
                    return
                }
            }
        }
        // Una llamada (u otra app que toma el audio): termina lo grabado.
        interrupcion = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let tipo = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard tipo == .began else { return }
            Task { @MainActor in await self?.terminar() }
        }
    }

    /// Para, sube lo que falta y la termina (la nube la pasa a texto).
    func terminar() async {
        guard estado == .grabando, let cid = id else { return }
        estado = .terminando
        reloj?.cancel()
        reloj = nil
        if let o = interrupcion { NotificationCenter.default.removeObserver(o) }
        interrupcion = nil
        mic?.parar()
        mic = nil
        salida?.finish()
        salida = nil
        soltarSesion()
        let r = await subida?.value ?? ResultadoSubida()
        subida = nil
        let api = Cuenta.compartida.api
        if r.subidos == 0 {
            try? await api.borrarConversacion(cid)
            aviso = "No llegó audio"
        } else {
            do {
                try await api.terminarConversacion(cid)
                if r.perdidos > 0 { aviso = "Faltaron \(r.perdidos) s" }
            } catch let e as ErrorApi {
                aviso = e.mensaje
            } catch {
                aviso = "No pude"
            }
        }
        id = nil
        estado = .quieto
        terminadas += 1
    }

    private func soltarSesion() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// La cola: de a un trozo, en orden; cada uno hasta 3 intentos.
    nonisolated private static func subir(_ flujo: AsyncStream<Data>, id: Int, api: ApiSintetica) async -> ResultadoSubida {
        var indice = 0
        var r = ResultadoSubida()
        for await trozo in flujo {
            var listo = false
            for intento in 0 ..< 3 {
                do {
                    try await api.subirTrozo(id, indice: indice, trozo)
                    listo = true
                    break
                } catch {
                    if intento < 2 { try? await Task.sleep(for: .seconds(Double(intento + 1))) }
                }
            }
            if listo { r.subidos += 1 } else { r.perdidos += 1 }
            indice += 1
        }
        return r
    }
}
