import SwiftUI

// Las piezas de la consola, como en web/src/lib/consola/consola.css.

/// Un rótulo grabado en la chapa: mayúsculas, ancho, con aire entre letras.
struct Grabado: View {
    let texto: String
    var color: Color = .gris
    init(_ texto: String, color: Color = .gris) {
        self.texto = texto
        self.color = color
    }

    var body: some View {
        Text(texto.uppercased()).font(Tipos.grabado).tracking(1.4).foregroundStyle(color).lineLimit(1)
    }
}

/// El título grande de cada pantalla.
struct Titular: View {
    let texto: String
    var tamano: CGFloat = 46
    init(_ texto: String, tamano: CGFloat = 46) {
        self.texto = texto
        self.tamano = tamano
    }

    var body: some View {
        Text(texto.uppercased()).font(Tipos.marca(tamano, .black)).tracking(-tamano * 0.04)
            .foregroundStyle(Color.papel).lineLimit(2).minimumScaleFactor(0.5)
    }
}

enum EstadoLed { case apagado, on, verde, ambar, rojo }

struct Led: View {
    var estado: EstadoLed = .on
    var tamano: CGFloat = 9

    private var color: Color? {
        switch estado {
        case .apagado: nil
        case .on: .led
        case .verde: .verde
        case .ambar: .ambar
        case .rojo: .rojo
        }
    }

    var body: some View {
        Circle().fill(color ?? Color.apagado).frame(width: tamano, height: tamano)
            .shadow(color: color ?? .clear, radius: color == nil ? 0 : tamano * 0.6)
            .accessibilityHidden(true)
    }
}

enum TipoTecla { case blanca, negra, naranja }

/// Una tecla mecánica: se hunde al apretarla (y queda hundida si `hundida`).
struct EstiloTecla: ButtonStyle {
    var tipo: TipoTecla = .blanca
    var chica = false
    var cuadrada = false
    var hundida = false
    var ancha = false
    @Environment(\.isEnabled) private var habilitada

    private var arriba: Color {
        switch tipo {
        case .blanca: Color(hex: 0xFBF9F5)
        case .negra: Color(hex: 0x3A3632)
        case .naranja: Color(hex: 0xFF8A5C)
        }
    }

    private var abajoColor: Color {
        switch tipo {
        case .blanca: Color(hex: 0xE9E4DC)
        case .negra: Color(hex: 0x1D1B18)
        case .naranja: Color(hex: 0xF2541A)
        }
    }

    private var base: Color {
        switch tipo {
        case .blanca: Color(hex: 0xA39C90)
        case .negra: Color.black
        case .naranja: Color(hex: 0x9A3209)
        }
    }

    private var letra: Color { tipo == .negra ? .papel : .tinta }

    func makeBody(configuration: Configuration) -> some View {
        let abajo = (configuration.isPressed || hundida) && habilitada
        let radio: CGFloat = chica || cuadrada ? 11 : 15
        let alto: CGFloat = cuadrada ? 44 : chica ? 40 : 52
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        let tamanoLetra: CGFloat = cuadrada ? 18 : chica ? 11 : 13
        return configuration.label
            .font(Tipos.marca(tamanoLetra, .heavy))
            .tracking(cuadrada ? 0 : 0.7)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(letra)
            .padding(.horizontal, cuadrada ? 0 : chica ? 14 : 22)
            .frame(minWidth: cuadrada ? 44 : nil, maxWidth: ancha ? .infinity : nil, minHeight: alto)
            .background(forma.fill(LinearGradient(colors: [arriba, abajoColor], startPoint: .top, endPoint: .bottom)))
            .overlay(forma.strokeBorder(LinearGradient(colors: [Color.white.opacity(tipo == .negra ? 0.18 : 0.7), Color.clear],
                                                       startPoint: .top, endPoint: .center), lineWidth: 1))
            .background(forma.fill(base).offset(y: abajo ? 1 : 6))
            .shadow(color: Color.black.opacity(abajo ? 0.2 : 0.45), radius: abajo ? 1 : 7, y: abajo ? 1 : 9)
            .offset(y: abajo ? 5 : 0)
            .padding(.bottom, 6)
            .opacity(habilitada ? 1 : 0.45)
            .animation(.easeOut(duration: 0.08), value: abajo)
    }
}

extension View {
    func tecla(_ tipo: TipoTecla = .blanca, chica: Bool = false, cuadrada: Bool = false, hundida: Bool = false, ancha: Bool = false) -> some View {
        buttonStyle(EstiloTecla(tipo: tipo, chica: chica, cuadrada: cuadrada, hundida: hundida, ancha: ancha))
    }
}

/// Un visor hundido, negro.
struct Visor<Contenido: View>: View {
    var relleno: CGFloat = 16
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { contenido }
            .padding(.vertical, relleno)
            .padding(.horizontal, relleno + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.hundido.shadow(.inner(color: .black.opacity(0.85), radius: 5, y: 3))))
    }
}

/// La placa naranja anodizada, con su trama de puntos.
struct PlacaNaranja<Contenido: View>: View {
    var relleno: CGFloat = 16
    var radio: CGFloat = 30
    @ViewBuilder let contenido: Contenido

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        VStack(alignment: .leading, spacing: 16) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    forma.fill(LinearGradient(stops: [.init(color: Color(hex: 0xFF7039), location: 0), .init(color: Color(hex: 0xF2541A), location: 0.55),
                                                      .init(color: Color(hex: 0xD9450F), location: 1)], startPoint: .top, endPoint: .bottom))
                    Trama().clipShape(forma)
                    forma.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.clear], startPoint: .top, endPoint: .center), lineWidth: 1.5)
                }
                .shadow(color: Color.black.opacity(0.7), radius: 24, y: 24)
            }
    }
}

/// La trama de puntos de la placa.
struct Trama: View {
    var body: some View {
        Canvas { ctx, tam in
            let paso: CGFloat = 7
            var camino = Path()
            var y: CGFloat = paso / 2
            while y < tam.height {
                var x: CGFloat = paso / 2
                while x < tam.width {
                    camino.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += paso
                }
                y += paso
            }
            ctx.fill(camino, with: .color(Color.black.opacity(0.14)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Una bandeja hundida en la placa naranja.
struct Bandeja<Contenido: View>: View {
    var relleno: CGFloat = 16
    var espacio: CGFloat = 14
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: espacio) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.tinta.opacity(0.12).shadow(.inner(color: .black.opacity(0.25), radius: 4, y: 2))))
    }
}

/// La chapa oscura de las tarjetas.
struct Chapa: ViewModifier {
    var radio: CGFloat = 28
    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        return content
            .background(forma.fill(LinearGradient(colors: [Color(hex: 0x2C2925), Color(hex: 0x1C1A17)], startPoint: .top, endPoint: .bottom)))
            .overlay(forma.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), Color.clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .clipShape(forma)
            .shadow(color: Color.black.opacity(0.7), radius: 20, y: 18)
    }
}

extension View {
    func chapa(radio: CGFloat = 28) -> some View { modifier(Chapa(radio: radio)) }
}

/// Un interruptor con LED.
struct Llave: View {
    let texto: String
    let prendida: Bool
    var ancha = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Led(estado: prendida ? .on : .apagado)
                Text(texto.uppercased()).font(Tipos.marca(10.5, .heavy)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(prendida ? Color.papel : Color.grisClaro)
            .padding(.horizontal, 12)
            .frame(maxWidth: ancha ? .infinity : nil, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.hundido.shadow(.inner(color: .black.opacity(0.85), radius: 4, y: 2))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(prendida ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: prendida)
    }
}

/// Un aviso corto (en un visor).
struct AvisoConsola: View {
    let texto: String
    var error = false
    var body: some View {
        HStack(spacing: 10) {
            Led(estado: error ? .rojo : .on)
            Text(texto).font(Tipos.marca(13, .bold)).foregroundStyle(Color.papel).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.hundido))
    }
}

/// Unos dígitos de visor, en brasa.
struct Digitos: View {
    let texto: String
    var chicos = false
    var body: some View {
        Text(texto).font(chicos ? Tipos.digitosChicos : Tipos.digitos).foregroundStyle(Color.brasa)
            .shadow(color: Color.led.opacity(0.45), radius: 9).lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Un campo de texto de visor.
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
        Visor(relleno: 12) {
            Grabado(rotulo)
            TextField("", text: $texto, prompt: Text(ayuda).foregroundColor(Color(hex: 0x5A524A)))
                .font(Tipos.marca(claro ? min(tamano, 18) : tamano, .black))
                .foregroundStyle(claro ? Color.papel : Color.brasa)
                .tint(Color.brasa)
                .keyboardType(teclado)
                .autocorrectionDisabled()
                .textInputAutocapitalization(teclado == .URL ? .never : .sentences)
                .focused($enfocado)
                .submitLabel(.done)
                .onSubmit(alTerminar)
                .onChange(of: enfocado) { _, si in if !si { alTerminar() } }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(enfocado ? Color.brasa : Color.clear, lineWidth: 2))
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
            ctx.fill(Path(roundedRect: CGRect(x: 4 * k, y: 3 * k, width: 11 * k, height: 20 * k), cornerRadius: 5.5 * k), with: .color(.naranja))
            var p = Path()
            p.move(to: CGPoint(x: 25 * k, y: 8 * k))
            p.addLine(to: CGPoint(x: 36 * k, y: 3 * k))
            p.addLine(to: CGPoint(x: 36 * k, y: 18 * k))
            p.addArc(center: CGPoint(x: 30.5 * k, y: 18 * k), radius: 5.5 * k, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .color(.naranja))
        }
        .frame(width: 36, height: 23)
        .accessibilityHidden(true)
    }
}
