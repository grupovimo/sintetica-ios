import SwiftUI

/// La foto real del robot con su pantalla viva encima, encastrada donde cae la
/// pantalla en la foto. Los mismos encuadres que web/src/lib/consola/modelo.ts.
struct Producto<Contenido: View>: View {
    let modelo: ModeloProducto
    var apagado = false
    var etiqueta = ""
    var radio: CGFloat = 32
    @ViewBuilder let pantalla: Contenido

    var body: some View {
        GeometryReader { g in
            ventana(g.size)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
        // La foto desborda la ventana (está corrida y agrandada): que no tape los toques de arriba.
        .contentShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
        .shadow(color: Color.black.opacity(0.8), radius: 24, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modelo.encuadre.alt)
    }

    private func ventana(_ t: CGSize) -> some View {
        let e = modelo.encuadre
        let w: CGFloat = t.width
        let h: CGFloat = t.height
        let fw: CGFloat = w * e.foto.ancho / 100
        let caja = CGRect(x: w * e.pantalla.izq / 100, y: h * e.pantalla.arriba / 100,
                          width: w * e.pantalla.ancho / 100, height: h * e.pantalla.alto / 100)
        return ZStack(alignment: .topLeading) {
            Color(hex: e.fondo)
            Image(e.imagen).resizable().interpolation(.high)
                .frame(width: fw, height: fw * Encuadre.proporcion(e.imagen))
                .offset(x: w * e.foto.izq / 100, y: h * e.foto.arriba / 100)
                .saturation(apagado ? 0.3 : 1)
                .brightness(apagado ? -0.32 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            encastre(caja.size)
                .frame(width: caja.width, height: caja.height)
                .clipped()
                .contentShape(Rectangle())
                .background(Color.black)
                .clipShape(modelo.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
                .opacity(apagado ? 0.25 : 1)
                .offset(x: caja.minX, y: caja.minY)
            if !etiqueta.isEmpty {
                cartel.frame(width: w - 32).offset(x: 16, y: h - 56).allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
    }

    /// Una pantalla apaisada en una caja de pie se agranda al 185 % (los
    /// costados, que suelen estar vacíos, quedan afuera).
    private func encastre(_ t: CGSize) -> some View {
        let agrandar = modelo.encuadre.apaisada(redonda: modelo.redonda)
        let ancho: CGFloat = agrandar ? t.width * Encuadre.agrandado : t.width
        let alto: CGFloat = agrandar ? ancho * CGFloat(modelo.proporcion) : t.height
        return pantalla.frame(width: ancho, height: alto).frame(width: t.width, height: t.height)
    }

    private var cartel: some View {
        HStack(spacing: 10) {
            Led(estado: apagado ? .apagado : .on)
            Text(etiqueta).font(Tipos.marca(13, .bold)).foregroundStyle(Color.papel).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.hundido.opacity(0.85)))
    }
}

/// La pantalla del núcleo del celu (la vista previa del robot abierto, o el
/// robot de prueba mismo). Hay una sola: el núcleo es uno por proceso.
struct PantallaNucleo: View {
    var alApretar: (Bool) -> Void = { _ in }
    @State private var apretado = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let imagen = cuadro()
            if let imagen {
                Image(decorative: imagen, scale: 1).resizable().interpolation(.high)
            } else {
                Color.pantalla
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !apretado { apretado = true; alApretar(true) } }
            .onEnded { _ in apretado = false; alApretar(false) })
        .accessibilityLabel("Pantalla en vivo")
    }

    private func cuadro() -> CGImage? {
        Nucleo.tick()
        return Nucleo.imagen()
    }
}

/// Una cara dibujada por el núcleo sin tocar la instancia (para el dock, donde
/// hay varios robots a la vez, y el laboratorio). Se anima con el tiempo.
struct PantallaDibujada: View {
    let config: String?
    let expresion: String
    let pantalla: Pantalla
    var fps: Double = 12
    var escala: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            if let img = dibujar(t) {
                Image(decorative: img, scale: 1).resizable().interpolation(.high)
            } else {
                Color.pantalla
            }
        }
        .accessibilityHidden(true)
    }

    private func dibujar(_ t: Double) -> CGImage? {
        // El núcleo dibuja hasta 640 de lado.
        let k = min(escala, 640.0 / Double(max(1, max(pantalla.ancho, pantalla.alto))))
        let w = max(16, Int(Double(pantalla.ancho) * k)), h = max(16, Int(Double(pantalla.alto) * k))
        let nombre = nombreDibujable(expresion)
        let c = Nucleo.parpadeo(t)
        return Nucleo.dibujarExpresion(config: config, nombre: nombre, ancho: w, alto: h, redonda: pantalla.redonda, t: t, cierre: c)
            ?? Nucleo.dibujarExpresion(config: nil, nombre: "neutral", ancho: w, alto: h, redonda: pantalla.redonda, t: t, cierre: c)
    }
}

/// Lo que se ve como una cara del motor de vida ("pomodoro:trabajo", una
/// animación o un dibujo propio caen en la neutral).
func nombreDibujable(_ e: String) -> String {
    if e.isEmpty || e.contains(":") { return "neutral" }
    return e
}

/// Una miniatura fija de una cara (cacheada por config y nombre).
@MainActor
enum Miniaturas {
    private static var cache: [String: UIImage] = [:]

    /// Cambiaron los sprites: las caras de imagen se ven distinto.
    static func vaciar() { cache.removeAll() }

    static func de(_ nombre: String, config: String?, pantalla: Pantalla) -> UIImage? {
        let clave = "\(config?.hashValue ?? 0)|\(nombre)|\(pantalla.ancho)x\(pantalla.alto)"
        if let i = cache[clave] { return i }
        let w = pantalla.redonda ? 120 : 160
        let h = pantalla.redonda ? 120 : max(16, Int((160 * pantalla.proporcion).rounded()))
        guard let cg = Nucleo.dibujarExpresion(config: config, nombre: nombre, ancho: w, alto: h, redonda: pantalla.redonda, t: 0.4) else { return nil }
        let i = UIImage(cgImage: cg)
        if cache.count > 400 { cache.removeAll() }
        cache[clave] = i
        return i
    }
}

/// Una miniatura de cara en su marquito.
struct MiniCara: View {
    let nombre: String
    let config: String?
    let pantalla: Pantalla
    var ancho: CGFloat = 72

    var body: some View {
        let forma = pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8))
        Group {
            if let i = Miniaturas.de(nombre, config: config, pantalla: pantalla) {
                Image(uiImage: i).resizable().interpolation(.high)
            } else {
                Color.black.overlay(Text("·").foregroundStyle(Color.gris))
            }
        }
        .frame(width: ancho, height: pantalla.redonda ? ancho : ancho * pantalla.proporcion)
        .clipShape(forma)
        .overlay(forma.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .accessibilityLabel(nombre)
    }
}

/// Una imagen del robot con sus cuadros (las animaciones se mueven).
struct ImagenAnimada: View {
    let cuadros: [UIImage]
    let duraciones: [Int]

    var body: some View {
        if cuadros.count <= 1 {
            if let c = cuadros.first { Image(uiImage: c).resizable().scaledToFit() } else { Color.clear }
        } else {
            let total = max(1, duraciones.reduce(0) { $0 + max(20, $1) })
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                Image(uiImage: cuadros[indice(ctx.date, total)]).resizable().scaledToFit()
            }
        }
    }

    private func indice(_ d: Date, _ total: Int) -> Int {
        var t = Int(d.timeIntervalSinceReferenceDate * 1000) % total
        for (i, ms) in duraciones.enumerated() {
            t -= max(20, ms)
            if t < 0 { return min(i, cuadros.count - 1) }
        }
        return 0
    }
}
