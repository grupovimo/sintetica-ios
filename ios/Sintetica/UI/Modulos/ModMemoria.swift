import SwiftUI

/// Un dato que el dueño le contó a su S1 (/v1/recuerdos; de la cuenta).
struct Recuerdo: Identifiable, Equatable {
    var clave = "", texto = ""
    var id: String { clave }
    init(_ o: [String: Any]) {
        clave = o["clave"] as? String ?? ""
        texto = o["texto"] as? String ?? ""
    }
}

extension ApiSintetica {
    func recuerdos() async throws -> (lista: [Recuerdo], max: Int) { leerRecuerdos(try await pedir("/v1/recuerdos")) }
    func sumarRecuerdo(_ texto: String) async throws -> (lista: [Recuerdo], max: Int) {
        leerRecuerdos(try await pedir("/v1/recuerdos", "POST", ["texto": texto]))
    }
    func sacarRecuerdo(_ clave: String) async throws -> (lista: [Recuerdo], max: Int) {
        let c = clave.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? clave
        return leerRecuerdos(try await pedir("/v1/recuerdos/\(c)", "DELETE"))
    }
    private func leerRecuerdos(_ o: [String: Any]) -> (lista: [Recuerdo], max: Int) {
        ((o["recuerdos"] as? [[String: Any]] ?? []).map(Recuerdo.init), o["max"] as? Int ?? 30)
    }
}

/// Memoria: lo que le contaste a tu S1 y no se olvida ("acordate que mi cumple
/// es el 3 de mayo"). Lo saben todos tus robots. Como
/// web/src/lib/consola/modulos/Memoria.svelte.
@MainActor
struct ModMemoria: View {
    let modelo: ModeloRobot
    @State private var lista: [Recuerdo] = []
    @State private var max = 30
    @State private var cargado = false
    @State private var nuevo = ""
    @State private var error = ""

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        if !modelo.esNube {
            SoloNube()
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("", text: $nuevo, prompt: Text("mi cumple es el 3 de mayo").foregroundColor(Color.tinta3))
                        .font(Tipos.marca(16, .bold)).foregroundStyle(Color.papel)
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
                        .onSubmit { sumar() }
                    Button { sumar() } label: { Text("+") }.tecla(.naranja, chica: true)
                        .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                if lista.isEmpty {
                    if cargado { Bandeja { Grabado("«acordate que mi cumple es el 3 de mayo»", color: Color.tinta.opacity(0.66)) } }
                } else {
                    ForEach(lista.reversed()) { r in
                        Bandeja {
                            HStack {
                                Text(r.texto).font(Tipos.marca(15, .black)).foregroundStyle(Color.tinta)
                                Spacer(minLength: 6)
                                Button { sacar(r) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).foregroundStyle(Color.tinta.opacity(0.5)).accessibilityLabel("Olvidar \(r.texto)")
                            }
                        }
                    }
                    HStack { Spacer(); Grabado("\(lista.count) de \(max)", color: Color.tinta.opacity(0.66)) }
                }
            }
            .task { await cargar() }
        }
    }

    private func cargar() async {
        do { (lista, max) = try await api.recuerdos() } catch { self.error = error.localizedDescription }
        cargado = true
    }

    private func sumar() {
        let t = String(nuevo.trimmingCharacters(in: .whitespaces).prefix(120))
        guard !t.isEmpty else { return }
        Task {
            do { (lista, max) = try await api.sumarRecuerdo(t); nuevo = "" } catch { self.error = error.localizedDescription }
        }
    }

    private func sacar(_ r: Recuerdo) {
        Task {
            do { (lista, max) = try await api.sacarRecuerdo(r.clave) } catch { self.error = error.localizedDescription }
        }
    }
}
