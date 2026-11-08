import Foundation
import Observation

/// Los eventos en vivo de la cuenta (SSE /v1/eventos), compartidos por todas
/// las pantallas: una sola conexión, que se reconecta sola con espera
/// creciente (1 s, 2 s, 4 s… hasta 30 s). Como web/src/lib/eventos.svelte.ts.
@MainActor
@Observable
final class EnVivo {
    static let compartido = EnVivo()
    private(set) var conectado = false
    @ObservationIgnored private var oyentes: [UUID: (EventoNube) -> Void] = [:]
    @ObservationIgnored private var tarea: Task<Void, Never>?

    /// Escucha mientras haga falta; devuelve con qué dejar de escuchar.
    func escuchar(_ f: @escaping (EventoNube) -> Void) -> UUID {
        let id = UUID()
        oyentes[id] = f
        if tarea == nil { arrancar() }
        return id
    }

    func dejar(_ id: UUID) {
        oyentes[id] = nil
        if oyentes.isEmpty {
            tarea?.cancel()
            tarea = nil
            conectado = false
        }
    }

    /// Después de entrar o salir de la cuenta.
    func reiniciar() {
        tarea?.cancel()
        tarea = nil
        conectado = false
        if !oyentes.isEmpty { arrancar() }
    }

    private func arrancar() {
        tarea = Task { [weak self] in
            var espera = 1.0
            while !Task.isCancelled {
                let cuenta = Cuenta.compartida
                if cuenta.activa {
                    do {
                        for try await e in cuenta.api.eventosCuenta() {
                            guard let self else { return }
                            if !self.conectado { self.conectado = true }
                            espera = 1
                            for o in self.oyentes.values { o(e) }
                        }
                    } catch let e as ErrorApi where e.estado == 401 {
                        cuenta.salir()
                    } catch {}
                }
                self?.conectado = false
                try? await Task.sleep(for: .seconds(espera))
                espera = min(30, espera * 2)
            }
        }
    }
}
