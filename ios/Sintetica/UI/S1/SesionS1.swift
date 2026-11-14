import Foundation
import Observation
import QuartzCore
import SwiftUI

/// Un solo estado para toda la app (APP.md, regla 8): chip, LED y cara
/// cambian juntos en todas las pantallas.
enum EstadoS1: Equatable {
    case conectando, despierta, durmiendo, escuchando, hablando, pensando, sinConexion

    var texto: String {
        switch self {
        case .conectando: "Conectando"
        case .despierta: "Despierta"
        case .durmiendo: "Durmiendo"
        case .escuchando: "Escuchando"
        case .hablando: "Hablando"
        case .pensando: "Pensando"
        case .sinConexion: "Sin conexión"
        }
    }

    var led: Color {
        switch self {
        case .despierta, .escuchando, .hablando: .s1LedDespierta
        case .durmiendo, .pensando: .s1LedDurmiendo
        case .conectando, .sinConexion: .s1LedSin
        }
    }
}

/// Un mensaje del hilo de la charla.
struct MensajeS1: Identifiable, Equatable {
    let id = UUID()
    var deMi: Bool
    var texto: String
    /// La cara de la respuesta (la de 32 al lado).
    var expresion = ""
    /// La S1 hizo o mostró algo: va la pantalla de 72 (APP.md, regla 2).
    var hizo = false
    /// No llegó: la cara sorprendida y "Reintentar".
    var fallo = false
    /// Mío y sin mandar (sin conexión).
    var sinEnviar = false
    /// Lo que hay que volver a mandar si falló.
    var pedido = ""
}

/// La S1 abierta: su modelo (config, estado en vivo), la voz en tiempo real y
/// el hilo de la charla. Vive mientras sea la S1 elegida, aunque se abran
/// pantallas encima (así no se corta la conexión al entrar a un módulo).
@MainActor
@Observable
final class SesionS1 {
    let id: String
    let modelo: ModeloRobot
    let conversacion = Conversacion()
    var puedeHablar = false
    var charla: Charla?
    var hilo: [MensajeS1] = []
    var pensando = false
    @ObservationIgnored private var abierta = false

    init(id: String) {
        self.id = id
        modelo = ModeloRobot(id: id)
    }

    func abrir() async {
        guard !abierta else { return }
        abierta = true
        conversacion.alCara = { [modelo] n in modelo.caraDeConversacion(n) }
        conversacion.alMirar = { [modelo] x, y in modelo.mirar(x, y) }
        await modelo.abrir()
        await mirarCharlaYVoz()
    }

    func reintentar() async {
        await modelo.abrir()
        await mirarCharlaYVoz()
    }

    func cerrar() {
        conversacion.cortar()
        modelo.cerrar()
        abierta = false
    }

    /// La charla siempre está con la nube (sin IA charla su motor propio); la
    /// voz en tiempo real, si ElevenLabs está conectado y con minutos.
    private func mirarCharlaYVoz() async {
        guard modelo.esNube else { charla = nil; puedeHablar = false; return }
        let c = (try? await Cuenta.compartida.api.charla()) ?? Charla()
        charla = c.disponible ? c : nil
        if let v = try? await Cuenta.compartida.api.vozEleven() {
            puedeHablar = v.conectado && v.topeMinutos > 0
        }
    }

    var nombre: String { modelo.nombre == "Tu robot" ? "Tu S1" : modelo.nombre }

    var estado: EstadoS1 {
        switch modelo.fase {
        case .conectando: return .conectando
        case .error: return .sinConexion
        case .lista: break
        }
        if !modelo.conectado { return .sinConexion }
        switch conversacion.estado {
        case .escucha: return .escuchando
        case .habla: return .hablando
        case .conectando: return .pensando
        case .quieto: break
        }
        if pensando { return .pensando }
        if modelo.estado?.dormido == true { return .durmiendo }
        return .despierta
    }

    /// La cara que se ve ahora (para las caras dibujadas, no la de la pantalla viva).
    var expresion: String {
        switch estado {
        case .durmiendo: "dormido"
        case .pensando, .conectando: "pensando"
        case .sinConexion: "neutral"
        default: nombreDibujable(modelo.estado?.expresion ?? "neutral")
        }
    }

    // --- La voz ---

    /// Mantené para hablar: arranca la charla en tiempo real (si ya está, la corta).
    func hablar() {
        if conversacion.activa { conversacion.cortar(); return }
        Task { await conversacion.empezar(id: id) }
    }

    // --- La charla ---

    /// Le escribís: con la nube contesta ella (su motor o la IA); por
    /// Bluetooth o de prueba, lo dice en su pantalla.
    func enviar(_ texto: String) async {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !pensando else { return }
        hilo.append(MensajeS1(deMi: true, texto: t))
        await responder(t)
    }

    func reintentar(_ m: MensajeS1) async {
        hilo.removeAll { $0.id == m.id }
        await responder(m.pedido)
    }

    private func responder(_ t: String) async {
        pensando = true
        defer { pensando = false }
        if charla != nil {
            do {
                let r = try await Cuenta.compartida.api.charlarDetalle(id, cortarBytes(t, MAX_CHARLA))
                charla?.quedan = r.quedan
                hilo.append(MensajeS1(deMi: false, texto: r.texto, expresion: r.expresion.isEmpty ? (modelo.estado?.expresion ?? "contento") : r.expresion,
                                      hizo: !r.accion.isEmpty))
            } catch let e as ErrorApi {
                let texto = e.estado == 429 ? "Por hoy ya charlamos mucho." : e.estado == 503 ? "Hoy no puedo charlar." : "No me llegó."
                hilo.append(MensajeS1(deMi: false, texto: texto, expresion: "sorpresa", fallo: e.estado != 429, pedido: t))
            } catch {
                hilo.append(MensajeS1(deMi: false, texto: "No me llegó.", expresion: "sorpresa", fallo: true, pedido: t))
            }
            return
        }
        if await modelo.decir(t) != nil, let i = hilo.lastIndex(where: { $0.deMi && $0.texto == t }) {
            hilo[i].sinEnviar = true
        }
    }
}

/// El cuadro de la pantalla viva (el núcleo del celu), compartido: el header,
/// el Inicio y la charla lo leen a la vez sin adelantar el núcleo dos veces.
@MainActor
enum CuadroVivo {
    private static var ultimo: CFTimeInterval = 0
    private static var cuadro: CGImage?

    static func actual() -> CGImage? {
        let ahora = CACurrentMediaTime()
        if cuadro == nil || ahora - ultimo > 1.0 / 40 {
            Nucleo.tick()
            cuadro = Nucleo.imagen()
            ultimo = ahora
        }
        return cuadro
    }
}

/// La S1 elegida (la que se abre en el Inicio), guardada en el celu.
@MainActor
@Observable
final class EleccionS1 {
    static let compartida = EleccionS1()
    private(set) var id: String?

    init() { id = UserDefaults.standard.string(forKey: "s1.elegida") }

    func elegir(_ nuevo: String?) {
        id = nuevo
        if let nuevo { UserDefaults.standard.set(nuevo, forKey: "s1.elegida") } else { UserDefaults.standard.removeObject(forKey: "s1.elegida") }
    }
}
