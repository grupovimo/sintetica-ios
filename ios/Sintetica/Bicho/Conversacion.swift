@preconcurrency import AVFoundation
import Foundation
import Observation

/// Hablarle en tiempo real: el agente de ElevenLabs de este robot (la cuenta
/// del dueño), por el websocket con la URL firmada que da la nube
/// (GET /v1/bichos/{id}/conversacion). El audio va directo a ElevenLabs en
/// PCM de 16 kHz. Sus herramientas (poner_expresion y mirar) mueven la cara.
/// Los mensajes: elevenlabs.io/docs, "Agents Platform › WebSocket".
@MainActor
@Observable
final class Conversacion {
    enum Estado: Equatable { case quieto, conectando, escucha, habla }

    private(set) var estado: Estado = .quieto
    private(set) var quedan = 0
    var aviso = ""

    @ObservationIgnored var alCara: (String?) -> Void = { _ in }
    @ObservationIgnored var alMirar: (Double, Double) -> Void = { _, _ in }
    @ObservationIgnored private var ws: URLSessionWebSocketTask?
    @ObservationIgnored private var audio: AudioConversacion?
    @ObservationIgnored private var escucha: Task<Void, Never>?
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored private var expresion: String?
    @ObservationIgnored private var caras: Set<String> = []
    @ObservationIgnored private var sonando = 0

    var activa: Bool { estado != .quieto }

    func empezar(id: String) async {
        guard estado == .quieto else { cortar(); return }
        estado = .conectando
        // El permiso primero: así un "no" se ve como tal.
        let permiso = await AVAudioApplication.requestRecordPermission()
        guard permiso else { terminar(); avisar("Sin micrófono"); return }
        let c: PedidoConversacion
        do {
            c = try await Cuenta.compartida.api.conversacion(id)
        } catch let e as ErrorApi {
            terminar()
            avisar(e.estado == 429 ? "Por hoy ya hablaron" : e.estado == 404 ? "Sin ElevenLabs" : e.mensaje)
            return
        } catch {
            terminar(); avisar("No pude"); return
        }
        guard let url = URL(string: c.url) else { terminar(); avisar("No pude"); return }
        caras = Set(c.expresiones)
        let w = URLSession.shared.webSocketTask(with: url)
        ws = w
        w.resume()
        quedan = c.segundos
        escucha = Task { [weak self] in await self?.escuchar(w) }
        reloj = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.activa else { return }
                self.quedan -= 1
                if self.quedan <= 0 { self.cortar(); return }
            }
        }
    }

    func cortar() {
        ws?.cancel(with: .normalClosure, reason: nil)
        terminar()
    }

    private func terminar() {
        escucha?.cancel()
        reloj?.cancel()
        audio?.parar()
        audio = nil
        ws = nil
        sonando = 0
        if estado != .quieto { alCara(nil) }
        expresion = nil
        estado = .quieto
    }

    private func avisar(_ t: String) {
        aviso = t
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.aviso == t { self?.aviso = "" }
        }
    }

    // MARK: - Mensajes

    private func escuchar(_ w: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let m: URLSessionWebSocketTask.Message
            do { m = try await w.receive() } catch { break }
            var texto: String?
            switch m {
            case let .string(s): texto = s
            case let .data(d): texto = String(data: d, encoding: .utf8)
            @unknown default: break
            }
            guard let texto, let o = (try? JSONSerialization.jsonObject(with: Data(texto.utf8))) as? [String: Any] else { continue }
            recibir(o, w)
        }
        if estado != .quieto { terminar() }
    }

    private func mandar(_ o: [String: Any], _ w: URLSessionWebSocketTask) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        w.send(.string(s)) { _ in }
    }

    private func recibir(_ o: [String: Any], _ w: URLSessionWebSocketTask) {
        switch MensajeConversacion(o) {
        case let .inicio(muestras):
            arrancarAudio(muestras, w)
        case let .ping(evento):
            mandar(["type": "pong", "event_id": evento], w)
        case let .audio(pcm):
            guard let a = audio else { return }
            sonando += 1
            if estado != .habla { estado = .habla; alCara(expresion) }
            a.reproducir(pcm) { [weak self] in
                Task { @MainActor in self?.terminoUnPedazo() }
            }
        case .interrupcion:
            audio?.interrumpir()
            sonando = 0
            pasarAEscucha()
        case let .herramienta(nombre, id, parametros, respuesta):
            let r = herramienta(nombre, parametros)
            if respuesta { mandar(["type": "client_tool_result", "tool_call_id": id, "result": r, "is_error": false], w) }
        case .otro:
            break
        }
    }

    private func terminoUnPedazo() {
        sonando = max(0, sonando - 1)
        if sonando == 0 { pasarAEscucha() }
    }

    private func pasarAEscucha() {
        guard estado != .quieto, audio != nil else { return }
        estado = .escucha
        // Escuchando, pone cara de escuchar (si el agente no eligió otra).
        alCara(expresion ?? "escuchando")
    }

    private func herramienta(_ nombre: String, _ p: [String: String]) -> String {
        switch nombre {
        case "poner_expresion":
            guard let n = p["nombre"], !n.isEmpty, caras.isEmpty || caras.contains(n) else { return "no la tengo" }
            expresion = n
            alCara(n)
            return "ok"
        case "mirar":
            let x = Double(p["x"] ?? "0") ?? 0, y = Double(p["y"] ?? "0") ?? 0
            alMirar(max(-1, min(1, x / 100)), max(-1, min(1, y / 100)))
            return "ok"
        default:
            return "no la tengo"
        }
    }

    private func arrancarAudio(_ muestras: Double, _ w: URLSessionWebSocketTask) {
        let a = AudioConversacion(muestrasSalida: muestras) { pcm in
            let s = pcm.base64EncodedString()
            w.send(.string("{\"user_audio_chunk\":\"\(s)\"}")) { _ in }
        }
        do {
            try a.arrancar()
            audio = a
            estado = .escucha
            alCara("escuchando")
        } catch {
            cortar()
            avisar("Sin micrófono")
        }
    }
}

/// Un mensaje del servidor de la conversación (lo que se usa).
enum MensajeConversacion: Equatable {
    case inicio(Double)  // las muestras por segundo del audio del agente
    case ping(Int)
    case audio(Data)
    case interrupcion
    case herramienta(String, String, [String: String], Bool)
    case otro

    static func == (a: MensajeConversacion, b: MensajeConversacion) -> Bool {
        switch (a, b) {
        case let (.inicio(x), .inicio(y)): x == y
        case let (.ping(x), .ping(y)): x == y
        case let (.audio(x), .audio(y)): x == y
        case (.interrupcion, .interrupcion), (.otro, .otro): true
        case let (.herramienta(n, i, p, r), .herramienta(m, j, q, s)): n == m && i == j && p == q && r == s
        default: false
        }
    }

    init(_ o: [String: Any]) {
        switch o["type"] as? String ?? "" {
        case "conversation_initiation_metadata":
            let m = o["conversation_initiation_metadata_event"] as? [String: Any] ?? [:]
            self = .inicio(MensajeConversacion.muestras(m["agent_output_audio_format"] as? String ?? "pcm_16000"))
        case "ping":
            self = .ping(((o["ping_event"] as? [String: Any])?["event_id"] as? NSNumber)?.intValue ?? 0)
        case "audio":
            let b = (o["audio_event"] as? [String: Any])?["audio_base_64"] as? String ?? ""
            self = .audio(Data(base64Encoded: b) ?? Data())
        case "interruption":
            self = .interrupcion
        case "client_tool_call":
            let c = o["client_tool_call"] as? [String: Any] ?? [:]
            var p: [String: String] = [:]
            for (k, v) in c["parameters"] as? [String: Any] ?? [:] { p[k] = "\(v)" }
            self = .herramienta(c["tool_name"] as? String ?? "", c["tool_call_id"] as? String ?? "", p, c["expects_response"] as? Bool ?? false)
        default:
            self = .otro
        }
    }

    /// "pcm_16000" → 16000 (lo demás, 16 kHz).
    static func muestras(_ formato: String) -> Double {
        guard formato.hasPrefix("pcm_"), let n = Double(formato.dropFirst(4)) else { return 16000 }
        return n
    }
}

/// El audio de la conversación: el micrófono a PCM 16 kHz mono (con cancelación
/// de eco) y lo que dice el agente por el parlante.
final class AudioConversacion: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private let jugador = AVAudioPlayerNode()
    private let salida: AVAudioFormat
    private let entrada16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var convertidor: AVAudioConverter?
    private let alAudio: (Data) -> Void

    init(muestrasSalida: Double, alAudio: @escaping (Data) -> Void) {
        salida = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: muestrasSalida, channels: 1, interleaved: false)!
        self.alAudio = alAudio
    }

    func arrancar() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
        let mic = motor.inputNode
        try? mic.setVoiceProcessingEnabled(true)
        motor.attach(jugador)
        motor.connect(jugador, to: motor.mainMixerNode, format: salida)
        let formato = mic.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { throw ErrorBicho.rechazo("Sin micrófono") }
        convertidor = AVAudioConverter(from: formato, to: entrada16)
        mic.installTap(onBus: 0, bufferSize: 2048, format: formato) { [weak self] buf, _ in self?.convertir(buf) }
        motor.prepare()
        try motor.start()
        jugador.play()
    }

    private func convertir(_ buf: AVAudioPCMBuffer) {
        guard let c = convertidor else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: entrada16, frameCapacity: cap) else { return }
        var dado = false
        var error: NSError?
        c.convert(to: out, error: &error) { _, estado in
            if dado { estado.pointee = .noDataNow; return nil }
            dado = true
            estado.pointee = .haveData
            return buf
        }
        guard error == nil, out.frameLength > 0, let p = out.int16ChannelData else { return }
        alAudio(Data(bytes: p[0], count: Int(out.frameLength) * 2))
    }

    /// PCM de 16 bits little endian a la cola del parlante.
    func reproducir(_ pcm: Data, listo: @escaping @Sendable () -> Void) {
        guard let b = pcmAFlotante(pcm, formato: salida) else { listo(); return }
        jugador.scheduleBuffer(b) { listo() }
    }

    func interrumpir() {
        jugador.stop()
        jugador.play()
    }

    func parar() {
        motor.inputNode.removeTap(onBus: 0)
        jugador.stop()
        motor.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// PCM de 16 bits little endian a un buffer de flotantes (lo que toca el parlante).
func pcmAFlotante(_ pcm: Data, formato: AVAudioFormat) -> AVAudioPCMBuffer? {
    let n = pcm.count / 2
    guard n > 0, let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(n)), let canal = b.floatChannelData?[0] else { return nil }
    pcm.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
        for i in 0 ..< n {
            let v = Int16(littleEndian: r.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            canal[i] = Float(v) / 32768
        }
    }
    b.frameLength = AVAudioFrameCount(n)
    return b
}
