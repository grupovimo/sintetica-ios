import Foundation

/// Un bicho lejos, por la nube: los mismos bytes que por BLE, por la API. Lo
/// que cambia la config o las imágenes lo guarda la API y se lo lleva al bicho
/// (cuando se conecte, si está apagado); los comandos van directo.
@MainActor
final class TransporteNube: Transporte {
    let difusor = Difusor()
    private let api: ApiSintetica
    private let id: String
    private let conexion = UUID().uuidString
    private var eventos: Task<Void, Never>?
    private var ultimoEstado: [UInt8]?

    init(api: ApiSintetica, id: String) {
        self.api = api
        self.id = id
    }

    func conectar() async throws {
        ultimoEstado = try await api.bicho(id).estadoCrudo
        eventos = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await e in self.api.eventos(self.id) { self.recibir(e) }
                } catch {}
                try? await Task.sleep(for: .seconds(3))  // se cortó: reconectar
            }
        }
    }

    private func recibir(_ e: EventoNube) {
        switch e.tipo {
        case "estado":
            if let s = e.datos["crudo"] as? String, let d = Data(base64Encoded: s) {
                ultimoEstado = [UInt8](d)
                difusor.emitir(.estado, [UInt8](d))
            }
        case "marco":
            if let c = e.datos["car"] as? Int, let car = Car(rawValue: c), let s = e.datos["datos"] as? String, let d = Data(base64Encoded: s) {
                difusor.emitir(car, [UInt8](d))
            }
        default:
            break
        }
    }

    func escribir(_ car: Car, _ datos: [UInt8]) async throws {
        for (c, b) in try await api.marco(id, car: car.rawValue, datos: datos, conexion: conexion) {
            if let car = Car(rawValue: c) { difusor.emitir(car, b) }
        }
    }

    func leerEstado() async throws -> [UInt8] {
        if let e = ultimoEstado { return e }
        guard let e = try await api.bicho(id).estadoCrudo else { throw ErrorBicho.rechazo("Todavía no sé cómo está el bicho.") }
        ultimoEstado = e
        return e
    }

    func cerrar() { eventos?.cancel() }
}
