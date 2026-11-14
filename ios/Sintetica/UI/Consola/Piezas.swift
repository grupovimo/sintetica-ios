import SwiftUI

// Las piezas de siempre de los módulos, ahora con el sistema S1
// (marca/diseno/APP.md): teclas con relieve, superficies, campos y chips.

/// Un rótulo chico (caption fuerte, en tinta 2).
struct Grabado: View {
    let texto: String
    var color: Color = .gris
    init(_ texto: String, color: Color = .gris) {
        self.texto = texto
        self.color = color
    }

    var body: some View {
        Text(texto).font(S1Tipo.captionFuerte).foregroundStyle(color).lineLimit(1)
    }
}

/// El título de una pantalla o de un paso (28, en una línea si entra).
struct Titular: View {
    let texto: String
    var tamano: CGFloat = 28
    init(_ texto: String, tamano: CGFloat = 28) {
        self.texto = texto
        self.tamano = tamano
    }

    var body: some View {
        Text(texto).font(.system(size: min(28, max(17, tamano)), weight: .bold)).tracking(-0.5)
            .foregroundStyle(Color.s1Tinta).lineLimit(2).minimumScaleFactor(0.6)
    }
}

enum EstadoLed { case apagado, on, verde, ambar, rojo }

/// Un LED plano de 8 (como el del chip de estado).
struct Led: View {
    var estado: EstadoLed = .on
    var tamano: CGFloat = 8

    private var color: Color {
        switch estado {
        case .apagado: .s1Apagado
        case .on: .s1Naranja
        case .verde: .s1LedDespierta
        case .ambar: .ambar
        case .rojo: .s1Error
        }
    }

    var body: some View {
        Circle().fill(color).frame(width: tamano, height: tamano).accessibilityHidden(true)
    }
}

enum TipoTecla { case blanca, negra, naranja }

/// Una tecla: 48 de alto (40 la chica), radio 12, brillo arriba, 4 de canto y
/// se hunde 3 al tocarla. La naranja es la acción principal; la negra va en
/// tinta invertida. Hundida = seleccionada: tinta invertida, sin relieve.
struct EstiloTecla: ButtonStyle {
    var tipo: TipoTecla = .blanca
    var chica = false
    var cuadrada = false
    var hundida = false
    var ancha = false
    @Environment(\.isEnabled) private var habilitada

    private var arriba: Color {
        switch tipo {
        case .blanca: .s1TeclaBrillo
        case .negra: .s1Inv
        case .naranja: .s1NaranjaBrillo
        }
    }

    private var abajo: Color {
        switch tipo {
        case .blanca: .s1Tecla
        case .negra: .s1Inv
        case .naranja: .s1Naranja
        }
    }

    private var canto: Color {
        switch tipo {
        case .blanca: .s1Canto
        case .negra: .s1InvCanto
        case .naranja: .s1NaranjaCanto
        }
    }

    private var letra: Color {
        switch tipo {
        case .blanca: .s1Tinta
        case .negra: .s1InvTexto
        case .naranja: .s1TintaFija
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let seleccionada = hundida && tipo != .naranja
        let apretada = configuration.isPressed && habilitada && !seleccionada
        let alto: CGFloat = cuadrada ? 48 : chica ? 40 : 48
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(S1Tipo.cuerpoFuerte)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(seleccionada ? Color.s1InvTexto : letra)
            .padding(.horizontal, cuadrada ? 0 : chica ? 14 : 20)
            .frame(minWidth: cuadrada ? 48 : nil, maxWidth: ancha ? .infinity : nil, minHeight: alto)
            .background {
                if seleccionada {
                    forma.fill(Color.s1Inv)
                } else {
                    forma.fill(LinearGradient(colors: [arriba, abajo], startPoint: .top, endPoint: .bottom))
                        .overlay(forma.strokeBorder(Color.white.opacity(tipo == .blanca ? 0.5 : 0.25), lineWidth: 0.5).mask {
                            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                        })
                }
            }
            .background(forma.fill(seleccionada ? Color.clear : canto).offset(y: apretada ? 1 : 4))
            .offset(y: apretada ? 3 : 0)
            .padding(.bottom, seleccionada ? 0 : 4)
            .padding(.top, seleccionada ? 4 : 0)
            .opacity(habilitada ? 1 : 0.4)
            .animation(.easeOut(duration: 0.08), value: apretada)
    }
}

extension View {
    func tecla(_ tipo: TipoTecla = .blanca, chica: Bool = false, cuadrada: Bool = false, hundida: Bool = false, ancha: Bool = false) -> some View {
        buttonStyle(EstiloTecla(tipo: tipo, chica: chica, cuadrada: cuadrada, hundida: hundida, ancha: ancha))
    }
}

/// Las teclas grandes (los grupos del laboratorio, modos, juegos): tecla
/// clara, y en tinta invertida si están elegidas.
struct EstiloTeclaModulo: ButtonStyle {
    let elegido: Bool
    func makeBody(configuration: Configuration) -> some View {
        let apretada = configuration.isPressed && !elegido
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .foregroundStyle(elegido ? Color.s1InvTexto : Color.s1Tinta)
            .background(forma.fill(elegido ? AnyShapeStyle(Color.s1Inv)
                    : AnyShapeStyle(LinearGradient(colors: [Color.s1TeclaBrillo, Color.s1Tecla], startPoint: .top, endPoint: .bottom))))
            .background(forma.fill(elegido ? Color.clear : Color.s1Canto).offset(y: apretada ? 1 : 4))
            .offset(y: apretada ? 3 : 0)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.08), value: apretada)
    }
}

/// Un visor: ahora un campo (blanco de día, casi negro de noche).
struct Visor<Contenido: View>: View {
    var relleno: CGFloat = 16
    @ViewBuilder let contenido: Contenido

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) { contenido }
            .padding(.vertical, relleno)
            .padding(.horizontal, relleno + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(forma.fill(Color.s1Campo))
            .overlay(forma.strokeBorder(Color.s1Linea, lineWidth: 1))
    }
}

/// La placa de antes: ahora una tarjeta (superficie, radio 20). El naranja
/// queda para la acción principal y para la S1.
struct PlacaNaranja<Contenido: View>: View {
    var relleno: CGFloat = 16
    var radio: CGFloat = 20
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
    }
}

/// Una trama de puntos (la del parlante).
struct Trama: View {
    var paso: CGFloat = 7
    var color: Color = Color.black.opacity(0.14)
    var radio: CGFloat = 1

    var body: some View {
        Canvas { ctx, tam in
            var camino = Path()
            var y: CGFloat = paso / 2
            while y < tam.height {
                var x: CGFloat = paso / 2
                while x < tam.width {
                    camino.addEllipse(in: CGRect(x: x - radio, y: y - radio, width: radio * 2, height: radio * 2))
                    x += paso
                }
                y += paso
            }
            ctx.fill(camino, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Un grupo: superficie de radio 20.
struct Bandeja<Contenido: View>: View {
    var relleno: CGFloat = 16
    var espacio: CGFloat = 12
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: espacio) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
    }
}

/// Una tarjeta.
struct Chapa: ViewModifier {
    var radio: CGFloat = 20
    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        return content
            .background(forma.fill(Color.s1Superficie))
            .clipShape(forma)
    }
}

extension View {
    func chapa(radio: CGFloat = 20) -> some View { modifier(Chapa(radio: radio)) }
}

/// El interruptor del sistema: 52 × 32; apagado con borde de 2 en tinta 2,
/// prendido en tinta invertida.
struct Interruptor: View {
    let prendido: Bool

    var body: some View {
        ZStack(alignment: prendido ? .trailing : .leading) {
            Capsule().fill(prendido ? Color.s1Inv : Color.clear)
            Capsule().strokeBorder(prendido ? Color.s1Inv : Color.s1Tinta2, lineWidth: 2)
            Circle().fill(prendido ? Color.s1Fondo : Color.s1Tinta2).frame(width: 20, height: 20).padding(.horizontal, 6)
        }
        .frame(width: 52, height: 32)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: prendido)
        .accessibilityHidden(true)
    }
}

/// Un interruptor con su nombre (la llave de antes).
struct Llave: View {
    let texto: String
    let prendida: Bool
    var ancha = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Text(texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Interruptor(prendido: prendida)
            }
            .padding(.leading, 16).padding(.trailing, 8)
            .frame(maxWidth: ancha ? .infinity : nil, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Campo))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.s1Linea, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(texto)
        .accessibilityValue(prendida ? "Prendido" : "Apagado")
        .accessibilityAddTraits(prendida ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: prendida)
    }
}

/// Un aviso corto.
struct AvisoConsola: View {
    let texto: String
    var error = false
    var body: some View {
        HStack(spacing: 12) {
            Led(estado: error ? .rojo : .verde)
            Text(texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Superficie))
    }
}

/// Unos dígitos grandes.
struct Digitos: View {
    let texto: String
    var chicos = false
    var body: some View {
        Text(texto).font(chicos ? Tipos.digitosChicos : S1Tipo.dato).foregroundStyle(Color.s1Tinta)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Un campo de texto: su rótulo arriba y el campo de 48.
struct CampoVisor: View {
    let rotulo: String
    @Binding var texto: String
    var ayuda = ""
    var claro = false
    var tamano: CGFloat = 24
    var teclado: UIKeyboardType = .default
    var alTerminar: () -> Void = {}
    @FocusState private var enfocado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if !rotulo.isEmpty { Grabado(rotulo) }
            TextField("", text: $texto, prompt: Text(ayuda).foregroundColor(Color.s1Tinta3))
                .font(.system(size: claro ? 15 : min(22, max(15, tamano)), weight: claro ? .regular : .bold))
                .foregroundStyle(Color.s1Tinta)
                .tint(Color.s1Naranja)
                .keyboardType(teclado)
                .autocorrectionDisabled()
                .textInputAutocapitalization(teclado == .URL || teclado == .emailAddress ? .never : .sentences)
                .focused($enfocado)
                .submitLabel(.done)
                .onSubmit(alTerminar)
                .onChange(of: enfocado) { _, si in if !si { alTerminar() } }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(forma.fill(Color.s1Campo))
                .overlay(forma.strokeBorder(enfocado ? Color.s1Tinta : Color.s1Linea, lineWidth: enfocado ? 2 : 1))
        }
    }
}

/// Un flujo: acomoda las piezas en renglones (como flex-wrap).
struct Flujo: Layout {
    var espacio: CGFloat = 8
    var renglon: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, altoRenglon: CGFloat = 0, maximo: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho {
                y += altoRenglon + renglon
                x = 0
                altoRenglon = 0
            }
            x += t.width + espacio
            maximo = max(maximo, x - espacio)
            altoRenglon = max(altoRenglon, t.height)
        }
        return CGSize(width: min(ancho, maximo), height: y + altoRenglon)
    }

    func placeSubviews(in caja: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = caja.minX, y = caja.minY, altoRenglon: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > caja.minX, x + t.width > caja.maxX {
                y += altoRenglon + renglon
                x = caja.minX
                altoRenglon = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            altoRenglon = max(altoRenglon, t.height)
        }
    }
}

/// La marca: las dos piezas naranjas del logo.
struct Marca: View {
    var body: some View {
        Canvas { ctx, tam in
            let k = tam.width / 40
            ctx.fill(Path(roundedRect: CGRect(x: 4 * k, y: 3 * k, width: 11 * k, height: 20 * k), cornerRadius: 5.5 * k), with: .color(.s1Naranja))
            var p = Path()
            p.move(to: CGPoint(x: 25 * k, y: 8 * k))
            p.addLine(to: CGPoint(x: 36 * k, y: 3 * k))
            p.addLine(to: CGPoint(x: 36 * k, y: 18 * k))
            p.addArc(center: CGPoint(x: 30.5 * k, y: 18 * k), radius: 5.5 * k, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .color(.s1Naranja))
        }
        .frame(width: 36, height: 23)
        .accessibilityHidden(true)
    }
}
