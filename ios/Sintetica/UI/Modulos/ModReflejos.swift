import SwiftUI

/// Reflejos: un patchbay. A la izquierda lo que le pasa, a la derecha cómo
/// reacciona; un cable los une. Se guardan como reglas propias simples
/// ({si, entonces: ["reflejo:x"]}); las complejas quedan para el Laboratorio.
/// Como web/src/lib/consola/modulos/Reflejos.svelte.
let ENTRADAS_REFLEJO = ["tacto", "caricia", "doble-toque", "muchos-toques", "levantado", "sacudida-fuerte", "boca-abajo", "caida", "volvio"]
let SALIDAS_REFLEJO: [(String, String)] = [
    ("contento", "Contento"), ("enamorado", "Enamorado"), ("risa", "Se ríe"), ("guino", "Guiña"), ("sorpresa", "Sorpresa"),
    ("verguenza", "Vergüenza"), ("mareado", "Mareado"), ("enojado", "Se enoja"), ("ofendido", "Ofendido"),
]

/// Una regla de reflejo simple (la que maneja el patchbay).
func esReflejoSimple(_ r: Regla) -> Bool {
    guard ENTRADAS_REFLEJO.contains(r.si), r.y == nil, r.entonces.count == 1, r.entonces[0].hasPrefix("reflejo:") else { return false }
    let s = String(r.entonces[0].dropFirst(8))
    return SALIDAS_REFLEJO.contains { $0.0 == s }
}

/// Los cables: entrada → salida.
func cablesDe(_ reglas: [Regla]) -> [String: String] {
    var c: [String: String] = [:]
    for r in reglas where esReflejoSimple(r) { c[r.si] = String(r.entonces[0].dropFirst(8)) }
    return c
}

/// Conecta (o desconecta, con salida nil) una entrada.
func conectarReflejo(_ reglas: [Regla], _ entrada: String, _ salida: String?) -> [Regla] {
    var otras = reglas.filter { !(esReflejoSimple($0) && $0.si == entrada) }
    if let salida { otras.append(Regla(si: entrada, entonces: ["reflejo:\(salida)"])) }
    return Array(otras.prefix(24))
}

struct ModReflejos: View {
    let modelo: ModeloRobot
    @State private var elegida: String?
    private let fila: CGFloat = 52
    private let movimiento: Set<String> = ["levantado", "sacudida-fuerte", "boca-abajo", "caida"]

    var body: some View {
        let cables = cablesDe(modelo.config.reglas)
        let sinMovimiento = !modelo.producto.tiene(.movimiento)
        VStack(alignment: .leading, spacing: 14) {
            Grabado(elegida.map { "\(NOMBRES_EVENTO[$0] ?? $0) → ¿qué hace?" } ?? "Uní un punto con otro", color: Color.tinta.opacity(0.7))
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(ENTRADAS_REFLEJO, id: \.self) { e in
                        jackEntrada(e, conectada: cables[e] != nil, apagada: sinMovimiento && movimiento.contains(e))
                    }
                }
                Cables(cables: cables, elegida: elegida, fila: fila)
                    .frame(width: 44, height: fila * CGFloat(ENTRADAS_REFLEJO.count))
                VStack(spacing: 0) {
                    ForEach(SALIDAS_REFLEJO, id: \.0) { s, t in
                        jackSalida(s, t, conectada: cables.values.contains(s), elegida: elegida.map { cables[$0] == s } ?? false)
                    }
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x1C1A17).shadow(.inner(color: .black.opacity(0.8), radius: 6, y: 3))))
            if sinMovimiento { Label("No siente el movimiento", systemImage: "move.3d").font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8)) }
        }
    }

    private func jackEntrada(_ e: String, conectada: Bool, apagada: Bool) -> some View {
        let sel = elegida == e
        return Button { elegida = sel ? nil : e } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(NOMBRES_EVENTO[e] ?? e).font(Tipos.marca(11.5, .bold)).multilineTextAlignment(.trailing)
                    .foregroundStyle(sel || conectada ? Color.papel : Color.grisClaro).lineLimit(2).minimumScaleFactor(0.8)
                Toma(conectada: conectada, elegida: sel, disponible: false)
            }
            .frame(height: fila)
        }
        .buttonStyle(.plain)
        .disabled(apagada)
        .opacity(apagada ? 0.35 : 1)
        .accessibilityAddTraits(sel ? [.isSelected] : [])
    }

    private func jackSalida(_ s: String, _ t: String, conectada: Bool, elegida esta: Bool) -> some View {
        Button {
            guard let e = elegida else { return }
            let actual = cablesDe(modelo.config.reglas)[e]
            let salida: String? = actual == s ? nil : s
            modelo.cambiar { $0.reglas = conectarReflejo($0.reglas, e, salida) }
            elegida = nil
        } label: {
            HStack(spacing: 8) {
                Toma(conectada: conectada, elegida: esta, disponible: elegida != nil)
                Text(t).font(Tipos.marca(11.5, .bold)).foregroundStyle(conectada ? Color.papel : Color.grisClaro).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(height: fila)
        }
        .buttonStyle(.plain)
        .disabled(elegida == nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: conectada)
    }
}

/// Una toma de patchbay.
private struct Toma: View {
    let conectada: Bool
    let elegida: Bool
    let disponible: Bool
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x24211E))
            Circle().fill(Color(hex: 0x3A3632)).padding(2)
            Circle().fill(Color(hex: 0x6B645B)).padding(8)
            Circle().fill(conectada ? Color.brasa : Color(hex: 0x050505)).padding(9)
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().stroke(elegida ? Color.brasa : disponible ? Color.brasa.opacity(0.35) : Color.clear, lineWidth: elegida ? 3 : 2).padding(-3))
        .shadow(color: elegida ? Color.led : .clear, radius: 8)
    }
}

/// Los cables entre las dos columnas.
private struct Cables: View {
    let cables: [String: String]
    let elegida: String?
    let fila: CGFloat

    var body: some View {
        Canvas { ctx, tam in
            for (i, e) in ENTRADAS_REFLEJO.enumerated() {
                guard let s = cables[e], let j = SALIDAS_REFLEJO.firstIndex(where: { $0.0 == s }) else { continue }
                let y0 = CGFloat(i) * fila + fila / 2, y1 = CGFloat(j) * fila + fila / 2
                var p = Path()
                p.move(to: CGPoint(x: -6, y: y0))
                p.addCurve(to: CGPoint(x: tam.width + 6, y: y1), control1: CGPoint(x: tam.width * 0.45, y: y0 + 26), control2: CGPoint(x: tam.width * 0.55, y: y1 + 26))
                let color = elegida == e ? Color.ambar : Color.led
                ctx.drawLayer { capa in
                    capa.addFilter(.shadow(color: .black.opacity(0.6), radius: 3, y: 4))
                    capa.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
