import SwiftUI

/// Una perilla: se gira arrastrando para arriba o abajo. Con VoiceOver es un
/// control ajustable (como un slider). Como web/src/lib/consola/Perilla.svelte.
struct Perilla: View {
    let nombre: String
    let valor: Double
    var min: Double = 0
    var max: Double = 1
    var paso: Double = 0.05
    var mostrar: ((Double) -> String)? = nil
    var tamano: CGFloat = 60
    let alCambiar: (Double) -> Void
    @State private var desde: Double?

    private var fraccion: Double { Swift.max(0, Swift.min(1, (valor - min) / (max - min))) }
    private var texto: String { mostrar?(valor) ?? String(Int(((valor - min) / (max - min) * 100).rounded())) }

    private func ajustar(_ v: Double) {
        let r = (Swift.min(max, Swift.max(min, v)) / paso).rounded() * paso
        let limpio = (r * 10000).rounded() / 10000
        if abs(limpio - valor) > 0.00001 { alCambiar(limpio) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Escala(fraccion: fraccion).frame(width: tamano + 18, height: tamano + 18)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x3E3A35), Color(hex: 0x161412)], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: tamano * 0.6))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.15), Color.clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                    .background(Circle().fill(Color.black).offset(y: 5))
                    .shadow(color: Color(hex: 0x501400).opacity(0.7), radius: 6, y: 9)
                    .overlay(alignment: .top) {
                        Capsule().fill(Color.brasa).frame(width: 5, height: tamano * 0.26).padding(.top, tamano * 0.07)
                            .shadow(color: Color.led, radius: 4)
                    }
                    .rotationEffect(.degrees(-135 + fraccion * 270))
                    .frame(width: tamano, height: tamano)
                    .animation(.easeOut(duration: 0.12), value: fraccion)
            }
            .frame(width: tamano + 18, height: tamano + 18)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if desde == nil { desde = valor }
                        ajustar((desde ?? valor) + Double(-g.translation.height) / 160 * (max - min))
                    }
                    .onEnded { _ in desde = nil }
            )
            Grabado(nombre, color: Color.tinta.opacity(0.7))
            Text(texto).font(Tipos.marca(14, .black).monospacedDigit()).foregroundStyle(Color.brasa)
                .frame(minWidth: 44).padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.8), radius: 3, y: 2))))
        }
        .sensoryFeedback(.selection, trigger: Int((valor / paso).rounded()))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
        .accessibilityValue(texto)
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: ajustar(valor + paso)
            case .decrement: ajustar(valor - paso)
            @unknown default: break
            }
        }
    }
}

/// La rueda de escala de la perilla: 11 marcas, prendidas hasta el valor.
private struct Escala: View {
    let fraccion: Double
    var body: some View {
        Canvas { ctx, tam in
            let c = CGPoint(x: tam.width / 2, y: tam.height / 2)
            let r = tam.width / 2
            for i in 0 ... 10 {
                let a = (-135.0 + Double(i) * 27) * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * r * 0.86, y: c.y - cos(a) * r * 0.86))
                p.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.98, y: c.y - cos(a) * r * 0.98))
                let prendida = Double(i) / 10 <= fraccion + 0.001
                ctx.stroke(p, with: .color(prendida ? Color.tinta : Color.tinta.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Los presets del dial, en el orden de la web (Dial.svelte).
let PRESETS_DIAL = ["picaro", "timido", "carinoso", "curioso", "dormilon", "grunon", "electrico", "equilibrado"]

/// El dial de personalidad: ocho posiciones alrededor de una perilla grande.
struct Dial: View {
    let valor: String
    let alCambiar: (String) -> Void

    private var indice: Int { Swift.max(0, PRESETS_DIAL.firstIndex(of: valor) ?? 0) }

    var body: some View {
        ZStack {
            perilla.position(x: 150, y: 140)
            ForEach(Array(PRESETS_DIAL.enumerated()), id: \.offset) { j, p in
                opcion(j, p)
            }
        }
        .frame(width: 300, height: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carácter")
    }

    private var perilla: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(hex: 0xFBF9F5), Color(hex: 0xD4CCBF), Color(hex: 0xFBF9F5), Color(hex: 0xCFC7B9), Color(hex: 0xFBF9F5)],
                                      center: .center, startAngle: .degrees(20), endAngle: .degrees(380)))
                .background(Circle().fill(Color(hex: 0x8F887C)).offset(y: 9))
                .shadow(color: Color(hex: 0x501400).opacity(0.6), radius: 14, y: 18)
            Capsule().fill(Color.naranja).frame(width: 7, height: 40).offset(y: -45)
                .rotationEffect(.degrees(Double(indice) * 45))
                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: indice)
            Circle().fill(RadialGradient(colors: [Color.papel, Color(hex: 0xBDB4A6)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 30))
                .frame(width: 46, height: 46)
        }
        .frame(width: 150, height: 150)
        .sensoryFeedback(.selection, trigger: indice)
    }

    private func opcion(_ j: Int, _ p: String) -> some View {
        let a = (-90.0 + Double(j) * 45) * .pi / 180
        let elegida = valor == p
        return Button { alCambiar(p) } label: {
            Text((NOMBRES_PRESET[p] ?? p).uppercased())
                .font(Tipos.marca(10.5, .heavy)).tracking(0.6)
                .foregroundStyle(elegida ? Color.white : Color.tinta.opacity(0.78))
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(elegida ? Color.tinta : Color.clear))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .position(x: 150 + cos(a) * 128, y: 140 + sin(a) * 118)
        .accessibilityAddTraits(elegida ? [.isSelected] : [])
    }
}

/// Un pad 2D: se arrastra un punto (x a los costados, y arriba/abajo).
struct Pad: View {
    let nombre: String
    let x: Double, y: Double
    let minX: Double, maxX: Double, minY: Double, maxY: Double
    let alCambiar: (Double, Double) -> Void

    var body: some View {
        GeometryReader { g in
            let fx = (x - minX) / (maxX - minX)
            let fy = 1 - (y - minY) / (maxY - minY)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.85), radius: 5, y: 3)))
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: g.size.width * 0.8, height: 1)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: g.size.height * 0.8)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFB08A), Color(hex: 0xF2541A)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                    .frame(width: 26, height: 26)
                    .shadow(color: Color.led, radius: 8)
                    .position(x: fx * g.size.width, y: fy * g.size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let a = Swift.min(1, Swift.max(0, v.location.x / g.size.width))
                let b = Swift.min(1, Swift.max(0, v.location.y / g.size.height))
                alCambiar(((minX + a * (maxX - minX)) * 1000).rounded() / 1000, ((minY + (1 - b) * (maxY - minY)) * 1000).rounded() / 1000)
            })
            .onTapGesture(count: 2) { alCambiar(0, 0) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
        .accessibilityValue(String(format: "%.2f, %.2f", x, y))
        .accessibilityAdjustableAction { d in
            let p = (maxX - minX) / 30
            switch d {
            case .increment: alCambiar(Swift.min(maxX, x + p), y)
            case .decrement: alCambiar(Swift.max(minX, x - p), y)
            @unknown default: break
            }
        }
    }
}

/// Un visor de reloj con + y −.
struct VisorMasMenos: View {
    let rotulo: String
    let valor: String
    var chicos = false
    let menos: () -> Void
    let mas: () -> Void

    var body: some View {
        Visor(relleno: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Grabado(rotulo)
                    Digitos(texto: valor, chicos: chicos)
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Button(action: mas) { Image(systemName: "plus") }.tecla(.negra, cuadrada: true).accessibilityLabel("\(rotulo): más")
                    Button(action: menos) { Image(systemName: "minus") }.tecla(.negra, cuadrada: true).accessibilityLabel("\(rotulo): menos")
                }
            }
        }
    }
}
