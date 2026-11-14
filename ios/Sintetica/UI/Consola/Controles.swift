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
    private var texto: String {
        if let mostrar { return mostrar(valor) }
        let f: Double = (valor - min) / (max - min) * 100
        return String(Int(f.rounded()))
    }

    private var angulo: Double { -135 + fraccion * 270 }

    private func ajustar(_ v: Double) {
        let r = (Swift.min(max, Swift.max(min, v)) / paso).rounded() * paso
        let limpio = (r * 10000).rounded() / 10000
        if abs(limpio - valor) > 0.00001 { alCambiar(limpio) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Escala(fraccion: fraccion).frame(width: tamano + 18, height: tamano + 18)
                tapa
            }
            .frame(width: tamano + 18, height: tamano + 18)
            .contentShape(Circle())
            .gesture(arrastre)
            Grabado(nombre)
            visor
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

    private var arrastre: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if desde == nil { desde = valor }
                let delta: Double = Double(-g.translation.height) / 160 * (max - min)
                ajustar((desde ?? valor) + delta)
            }
            .onEnded { _ in desde = nil }
    }

    private var tapa: some View {
        let relleno = LinearGradient(colors: [Color.s1TeclaBrillo, Color.s1Tecla], startPoint: .top, endPoint: .bottom)
        let marca = Capsule().fill(Color.s1Naranja).frame(width: 5, height: tamano * 0.26).padding(.top, tamano * 0.07)
        return Circle().fill(relleno)
            .overlay(Circle().strokeBorder(Color.s1Linea, lineWidth: 1))
            .background(Circle().fill(Color.s1Canto).offset(y: 4))
            .overlay(alignment: .top) { marca }
            .rotationEffect(.degrees(angulo))
            .frame(width: tamano, height: tamano)
            .animation(.easeOut(duration: 0.12), value: fraccion)
    }

    private var visor: some View {
        Text(texto).font(S1Tipo.mono(13)).foregroundStyle(Color.s1Tinta)
            .frame(minWidth: 44).padding(.vertical, 4).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.s1Superficie))
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
                let grados: Double = -135.0 + Double(i) * 27
                let a: Double = grados * Double.pi / 180
                let sx = CGFloat(sin(a)), cy = CGFloat(cos(a))
                let r0: CGFloat = r * 0.86, r1: CGFloat = r * 0.98
                var p = Path()
                p.move(to: CGPoint(x: c.x + sx * r0, y: c.y - cy * r0))
                p.addLine(to: CGPoint(x: c.x + sx * r1, y: c.y - cy * r1))
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
                .fill(LinearGradient(colors: [Color.s1TeclaBrillo, Color.s1Tecla], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.s1Linea, lineWidth: 1))
                .background(Circle().fill(Color.s1Canto).offset(y: 6))
            Capsule().fill(Color.s1Naranja).frame(width: 7, height: 40).offset(y: -45)
                .rotationEffect(.degrees(Double(indice) * 45))
                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: indice)
            Circle().fill(Color.s1Superficie)
                .frame(width: 46, height: 46)
        }
        .frame(width: 150, height: 150)
        .sensoryFeedback(.selection, trigger: indice)
    }

    private func opcion(_ j: Int, _ p: String) -> some View {
        let grados: Double = -90.0 + Double(j) * 45
        let a: Double = grados * Double.pi / 180
        let x = CGFloat(150 + cos(a) * 128), y = CGFloat(140 + sin(a) * 118)
        let elegida = valor == p
        return Button { alCambiar(p) } label: {
            Text(NOMBRES_PRESET[p] ?? p)
                .font(elegida ? S1Tipo.captionFuerte : S1Tipo.caption)
                .foregroundStyle(elegida ? Color.s1InvTexto : Color.s1Tinta)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(elegida ? Color.s1Inv : Color.clear))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
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
            let fx = CGFloat((x - minX) / (maxX - minX))
            let fy = CGFloat(1 - (y - minY) / (maxY - minY))
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Campo)
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.s1Linea, lineWidth: 1)
                Rectangle().fill(Color.s1Linea).frame(width: g.size.width * 0.8, height: 1)
                Rectangle().fill(Color.s1Linea).frame(width: 1, height: g.size.height * 0.8)
                Circle()
                    .fill(Color.s1Naranja)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.s1NaranjaCanto).offset(y: 3))
                    .position(x: fx * g.size.width, y: fy * g.size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let a: Double = Swift.min(1, Swift.max(0, Double(v.location.x / g.size.width)))
                let b: Double = Swift.min(1, Swift.max(0, Double(v.location.y / g.size.height)))
                let nx: Double = minX + a * (maxX - minX)
                let ny: Double = minY + (1 - b) * (maxY - minY)
                alCambiar((nx * 1000).rounded() / 1000, (ny * 1000).rounded() / 1000)
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

/// Un stepper (48): − el valor +.
struct VisorMasMenos: View {
    let rotulo: String
    let valor: String
    var chicos = false
    let menos: () -> Void
    let mas: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grabado(rotulo)
            HStack(spacing: 8) {
                Button(action: menos) { Image(systemName: "minus").font(.system(size: 17, weight: .bold)) }
                    .tecla(cuadrada: true).accessibilityLabel("\(rotulo): menos")
                Text(valor).font(chicos ? Tipos.digitosChicos : S1Tipo.dato).foregroundStyle(Color.s1Tinta)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                Button(action: mas) { Image(systemName: "plus").font(.system(size: 17, weight: .bold)) }
                    .tecla(cuadrada: true).accessibilityLabel("\(rotulo): más")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
