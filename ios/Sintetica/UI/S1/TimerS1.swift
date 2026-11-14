import Foundation
import Observation
import SwiftUI

/// El timer de la S1: lo corre ella (se lo pide la charla: "Poné un timer de N
/// minutos para X") y la app lleva la cuenta para mostrarlo en Inicio, Hoy,
/// los headers, su pantalla y la pantalla bloqueada (TimerEnVivo). El que
/// está andando se guarda en el celu (UserDefaults): sobrevive a cerrar la
/// app. Como web/src/lib/s1/timer.svelte.ts.
@MainActor
@Observable
final class TimerS1 {
    struct Estado: Codable, Equatable {
        var etiqueta: String
        var total: Int
        /// Cuándo arrancó la cuenta de `restante` (nil = en pausa).
        var inicio: Date?
        var restante: Int
        /// Cuándo llegó a cero ("¡Listo!" queda un minuto).
        var listo: Date?
    }

    struct Reciente: Codable, Equatable, Identifiable {
        var etiqueta: String
        var minutos: Int
        var id: String { etiqueta.lowercased() }
    }

    static let porDefecto = [Reciente(etiqueta: "La pasta", minutos: 15), Reciente(etiqueta: "Huevo", minutos: 7), Reciente(etiqueta: "Té", minutos: 4)]

    let id: String
    private(set) var t: Estado?
    private(set) var recientes: [Reciente] = TimerS1.porDefecto
    private(set) var ahora = Date()
    /// Se lo pide a ella por la charla (lo pone la sesión).
    @ObservationIgnored var mandar: (String) -> Void = { _ in }
    /// Su nombre, para la pantalla bloqueada.
    @ObservationIgnored var nombreRobot: () -> String = { "Tu S1" }
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored private var ultimoPedido = ""

    private var clave: String { "timer.\(id)" }

    init(id: String) {
        self.id = id
        let d = UserDefaults.standard
        if let v = d.data(forKey: clave), let e = try? JSONDecoder().decode(Estado.self, from: v) { t = e }
        if let r = d.data(forKey: "timer.recientes"), let l = try? JSONDecoder().decode([Reciente].self, from: r), !l.isEmpty { recientes = l }
        andar()
    }

    private func guardar() {
        if let t, let d = try? JSONEncoder().encode(t) {
            UserDefaults.standard.set(d, forKey: clave)
        } else {
            UserDefaults.standard.removeObject(forKey: clave)
        }
        andar()
    }

    /// El reloj de un segundo, solo mientras hay un timer.
    private func andar() {
        if t != nil, reloj == nil {
            reloj = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.latir()
                }
            }
        } else if t == nil {
            reloj?.cancel()
            reloj = nil
        }
    }

    private func latir() {
        ahora = Date()
        guard let x = t else { return }
        if x.inicio != nil, restante <= 0, x.listo == nil {
            t = Estado(etiqueta: x.etiqueta, total: x.total, inicio: nil, restante: 0, listo: Date())
            TimerEnVivo.terminar()
            guardar()
        } else if let l = x.listo, Date().timeIntervalSince(l) > 60 {
            t = nil
            guardar()
        }
    }

    /// Los segundos que quedan (en pausa, los que quedaron).
    var restante: Int {
        guard let x = t else { return 0 }
        guard let i = x.inicio else { return x.restante }
        return max(0, x.restante - Int(ahora.timeIntervalSince(i).rounded()))
    }

    var activo: Bool { t != nil && t?.listo == nil }
    var corriendo: Bool { t?.inicio != nil }
    var pausado: Bool { t != nil && t?.inicio == nil && t?.listo == nil }
    var listo: Bool { t?.listo != nil }
    var total: Int { t?.total ?? 0 }
    var etiqueta: String { t?.etiqueta ?? "" }
    var texto: String { mmss(restante) }

    /// Lo que muestra su pantalla mientras hay timer.
    func pantalla() -> AnyView {
        AnyView(PantallaTimer(restante: restante, total: total, etiqueta: etiqueta, pausado: pausado, listo: listo))
    }

    private func pedir(_ min: Int, _ etiqueta: String) {
        let e = etiqueta.trimmingCharacters(in: .whitespaces)
        let para = e.isEmpty ? "" : " para \(e)"
        ultimoPedido = "Poné un timer de \(min) \(min == 1 ? "minuto" : "minutos")\(para)"
        mandar(ultimoPedido)
    }

    /// Arranca uno nuevo (se lo pide a ella por la charla).
    func empezar(minutos: Int, etiqueta: String = "") {
        let m = max(1, min(180, minutos))
        let e = etiqueta.trimmingCharacters(in: .whitespaces)
        ahora = Date()
        t = Estado(etiqueta: e, total: m * 60, inicio: Date(), restante: m * 60, listo: nil)
        guardar()
        recordar(m, e)
        TimerEnVivo.empezar(nombre: e.isEmpty ? "Timer" : e, robot: nombreRobot(), minutos: Double(m))
        pedir(m, e)
    }

    /// Lo que arrancó ella (lo pediste en la charla o con la voz).
    func desdeCharla(_ pedido: String) {
        if pedido == ultimoPedido { return }
        let p = pedido.lowercased()
        guard let r = p.range(of: #"(\d+(?:[.,]\d+)?)\s*(h|hora|horas|min|minuto|minutos|seg|segundo|segundos)?"#, options: .regularExpression) else { return }
        let trozo = String(p[r])
        let numero = trozo.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard let n = Double(numero.replacingOccurrences(of: ",", with: ".")) else { return }
        let unidad = trozo.dropFirst(numero.count).trimmingCharacters(in: .whitespaces)
        let s = Int((unidad.hasPrefix("h") ? n * 3600 : unidad.hasPrefix("s") ? n : n * 60).rounded())
        guard s > 0 else { return }
        var e = ""
        if let q = pedido.range(of: #"\bpara\s+(el\s+|la\s+|los\s+|las\s+)?"#, options: [.regularExpression, .caseInsensitive]) {
            e = String(pedido[q.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " .?!"))
            e = String(e.prefix(24))
        }
        ahora = Date()
        t = Estado(etiqueta: e, total: s, inicio: Date(), restante: s, listo: nil)
        guardar()
        TimerEnVivo.empezar(nombre: e.isEmpty ? "Timer" : e, robot: nombreRobot(), minutos: Double(s) / 60)
    }

    /// Ella lo canceló (se lo pidieron en la charla o con la voz).
    func seCancelo() {
        t = nil
        TimerEnVivo.terminar()
        guardar()
    }

    /// Le pidieron cancelarlo en la charla (no lo que mandó la app al pausar).
    func cancelarDesdeCharla(_ pedido: String) {
        if pedido == ultimoPedido { return }
        seCancelo()
    }

    func pausar() {
        guard var x = t, x.inicio != nil else { return }
        x.restante = restante
        x.inicio = nil
        t = x
        guardar()
        TimerEnVivo.pausar(true, restante: TimeInterval(x.restante))
        ultimoPedido = "Cancelá el timer"
        mandar(ultimoPedido)
    }

    func seguir() {
        guard pausado, var x = t else { return }
        let m = max(1, Int((Double(x.restante) / 60).rounded(.up)))
        x.restante = m * 60
        x.total = max(x.total, m * 60)
        x.inicio = Date()
        ahora = Date()
        t = x
        guardar()
        TimerEnVivo.pausar(false, restante: TimeInterval(m * 60))
        pedir(m, x.etiqueta)
    }

    func sumarMinuto() {
        guard var x = t, !listo else { return }
        let r = restante + 60
        x.restante = r
        x.total += 60
        x.inicio = x.inicio == nil ? nil : Date()
        ahora = Date()
        t = x
        guardar()
        TimerEnVivo.pausar(x.inicio == nil, restante: TimeInterval(r))
        if x.inicio != nil { pedir(Int((Double(r) / 60).rounded(.up)), x.etiqueta) }
    }

    func cancelar() {
        let corria = corriendo
        t = nil
        TimerEnVivo.terminar()
        guardar()
        if corria {
            ultimoPedido = "Cancelá el timer"
            mandar(ultimoPedido)
        }
    }

    /// El que se vuelve a usar sube primero (hasta 6).
    private func recordar(_ minutos: Int, _ etiqueta: String) {
        guard !etiqueta.isEmpty else { return }
        recientes = [Reciente(etiqueta: etiqueta, minutos: minutos)] + recientes.filter { $0.id != etiqueta.lowercased() }
        recientes = Array(recientes.prefix(6))
        if let d = try? JSONEncoder().encode(recientes) { UserDefaults.standard.set(d, forKey: "timer.recientes") }
    }
}
