import SwiftUI

// Los componentes del sistema S1 (marca/diseno/APP.md y "App S1 Sistema").

/// El relieve de las teclas: brillo arriba, 4 de canto, sombra suave; se
/// hunde 3 al tocarla. Naranja = la acción principal (una por pantalla).
struct EstiloRelieve: ButtonStyle {
    var naranja = false
    var radio: CGFloat = 12
    @Environment(\.isEnabled) private var habilitada

    func makeBody(configuration: Configuration) -> some View {
        let apretada = configuration.isPressed && habilitada
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        let arriba: Color = naranja ? .s1NaranjaBrillo : .s1TeclaBrillo
        let abajo: Color = naranja ? .s1Naranja : .s1Tecla
        let canto: Color = naranja ? .s1NaranjaCanto : .s1Canto
        let sombra: Color = naranja ? Color(hex: 0xA8360B, alfa: 0.28) : Color(hex: 0x0B0A09, alfa: 0.14)
        return configuration.label
            .foregroundStyle(naranja ? Color.s1TintaFija : Color.s1Tinta)
            .background(forma.fill(LinearGradient(colors: [arriba, abajo], startPoint: .top, endPoint: .bottom)))
            .overlay(forma.strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
            .background(
                forma.fill(canto).offset(y: apretada ? 1 : 4)
                    .shadow(color: sombra, radius: apretada ? 2 : 7, y: apretada ? 2 : 7)
            )
            .offset(y: apretada ? 3 : 0)
            .padding(.bottom, 4)
            .opacity(habilitada ? 1 : 0.4)
            .animation(.easeOut(duration: 0.08), value: apretada)
    }
}

/// El botón principal de 48 (naranja) o el secundario (tecla clara).
struct BotonS1: View {
    let texto: String
    var naranja = true
    let accion: () -> Void

    init(_ texto: String, naranja: Bool = true, accion: @escaping () -> Void) {
        self.texto = texto
        self.naranja = naranja
        self.accion = accion
    }

    var body: some View {
        Button(action: accion) {
            Text(texto).font(S1Tipo.cuerpoFuerte).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(EstiloRelieve(naranja: naranja))
    }
}

/// Una tecla de 72 (o 88 en el hub de Más): el ícono arriba y el nombre abajo.
struct TeclaAtajo: View {
    let icono: Icono
    let nombre: String
    var alto: CGFloat = 72
    var bloqueada = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 0) {
                IconoS1(icono)
                Spacer(minLength: 4)
                Text(nombre).font(S1Tipo.captionFuerte).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: alto, maxHeight: alto, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloRelieve())
        .disabled(bloqueada)
        .accessibilityLabel(nombre)
    }
}

/// La trama de parlante redonda de la tecla Hablar (44).
struct Rejilla: View {
    var tamano: CGFloat = 44
    var body: some View {
        Trama(paso: 7, color: Color(hex: 0x0B0A09, alfa: 0.72), radio: 1.6)
            .frame(width: tamano, height: tamano)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(hex: 0x0B0A09, alfa: 0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// La tecla Hablar: naranja, de 72, con su trama de parlante. Al apretarla
/// (no al soltarla) arranca; así se siente como "mantené para hablar".
struct TeclaHablar: View {
    let texto: String
    var activa = false
    let alApretar: () -> Void
    @State private var apretada = false
    @Environment(\.isEnabled) private var habilitada

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 16) {
            Rejilla()
            Text(texto).font(S1Tipo.seccion).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if activa { IconoS1(.sistema("stop.fill"), tamano: 20) }
        }
        .foregroundStyle(Color.s1TintaFija)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .background(forma.fill(LinearGradient(colors: [Color.s1NaranjaBrillo, Color.s1Naranja], startPoint: .top, endPoint: .bottom)))
        .background(
            forma.fill(Color.s1NaranjaCanto).offset(y: apretada ? 1 : 4)
                .shadow(color: Color(hex: 0xA8360B, alfa: 0.28), radius: apretada ? 2 : 8, y: apretada ? 2 : 7)
        )
        .offset(y: apretada ? 3 : 0)
        .padding(.bottom, 4)
        .opacity(habilitada ? 1 : 0.4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard habilitada, !apretada else { return }
                    apretada = true
                    alApretar()
                }
                .onEnded { _ in apretada = false }
        )
        .animation(.easeOut(duration: 0.08), value: apretada)
        .sensoryFeedback(.impact(weight: .medium), trigger: apretada)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texto)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { alApretar() }
    }
}

/// Un chip de 36: con borde, o en tinta invertida si está elegido.
struct ChipS1: View {
    let texto: String
    var elegido = false
    let accion: () -> Void

    init(_ texto: String, elegido: Bool = false, accion: @escaping () -> Void) {
        self.texto = texto
        self.elegido = elegido
        self.accion = accion
    }

    var body: some View {
        Button(action: accion) {
            Text(texto).font(elegido ? S1Tipo.cuerpoFuerte : S1Tipo.cuerpo).lineLimit(1)
                .foregroundStyle(elegido ? Color.s1InvTexto : Color.s1Tinta)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(elegido ? Color.s1Inv : Color.clear))
                .overlay(Capsule().strokeBorder(elegido ? Color.clear : Color.s1Linea, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: elegido)
    }
}

/// El segmentado de 48: la opción elegida en tinta invertida.
struct Segmentado: View {
    let opciones: [(clave: String, nombre: String)]
    let elegida: String
    let alElegir: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(opciones, id: \.clave) { o in
                let si = o.clave == elegida
                Button { alElegir(o.clave) } label: {
                    Text(o.nombre).font(si ? S1Tipo.cuerpoFuerte : S1Tipo.cuerpo).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(si ? Color.s1InvTexto : Color.s1Tinta2)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(si ? Color.s1Inv : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(si ? [.isSelected] : [])
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Superficie))
        .sensoryFeedback(.selection, trigger: elegida)
    }
}

/// El toggle del sistema (52 × 32) para los Toggle de SwiftUI.
struct EstiloInterruptor: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                Spacer(minLength: 8)
                Interruptor(prendido: configuration.isOn)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Prendido" : "Apagado")
    }
}

/// Un renglón: a la izquierda algo (un ícono en círculo, una pantalla),
/// título y detalle, y a la derecha un valor o una flecha. Con línea arriba.
struct FilaS1<Izquierda: View>: View {
    let titulo: String
    var detalle = ""
    var valor = ""
    var flecha = false
    @ViewBuilder let izquierda: Izquierda

    var body: some View {
        HStack(spacing: 12) {
            izquierda
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                if !detalle.isEmpty { Text(detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !valor.isEmpty { Text(valor).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).monospacedDigit() }
            if flecha { IconoS1(.adelante, tamano: 20).foregroundStyle(Color.s1Tinta2) }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// El círculo de 48 con un ícono (para las filas).
struct IconoEnCirculo: View {
    let icono: Icono
    var body: some View {
        IconoS1(icono).foregroundStyle(Color.s1Tinta)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.s1Superficie))
    }
}

/// El título de una sección (17, 700): 32 arriba y 12 abajo.
struct Seccion: View {
    let texto: String
    var arriba: CGFloat = 32
    init(_ texto: String, arriba: CGFloat = 32) {
        self.texto = texto
        self.arriba = arriba
    }

    var body: some View {
        Text(texto).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
            .padding(.top, arriba).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// El chip de estado: 28, con su LED y el estado (Despierta, Durmiendo…).
struct ChipEstado: View {
    let estado: EstadoS1
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(estado.led).frame(width: 8, height: 8)
            Text(estado.texto).font(S1Tipo.captionFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(height: 28)
        .overlay(Capsule().strokeBorder(Color.s1Linea, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: estado)
        .accessibilityElement(children: .combine)
    }
}

// --- La pantalla de la S1 ---

/// Los tamaños de su pantalla: 32 (charla), 48 (listas), 72 (header), 160 (detalle).
enum TamanoPantalla {
    case charla, lista, header, detalle

    var lado: CGFloat {
        switch self {
        case .charla: 32
        case .lista: 48
        case .header: 72
        case .detalle: 160
        }
    }

    var marco: CGFloat {
        switch self {
        case .charla: 3
        case .lista: 4
        case .header: 6
        case .detalle: 10
        }
    }

    var radio: CGFloat {
        switch self {
        case .charla: 8
        case .lista: 12
        case .header, .detalle: 20
        }
    }

    var radioPantalla: CGFloat {
        switch self {
        case .charla: 5
        case .lista: 8
        case .header, .detalle: 12
        }
    }
}

/// El marco naranja de su pantalla, con la pantalla negra adentro.
struct MarcoPantalla<Contenido: View>: View {
    let tamano: TamanoPantalla
    @ViewBuilder let contenido: Contenido

    var body: some View {
        let interior = tamano.lado - tamano.marco * 2
        let forma = RoundedRectangle(cornerRadius: tamano.radio, style: .continuous)
        contenido
            .frame(width: interior, height: interior)
            .background(Color.s1Pantalla)
            .clipShape(RoundedRectangle(cornerRadius: tamano.radioPantalla, style: .continuous))
            .frame(width: tamano.lado, height: tamano.lado)
            .background(forma.fill(Color.s1Naranja))
            .overlay(
                forma.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.18)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

/// Su cara en vivo (la pantalla del núcleo del celu), llenando la caja.
struct CaraEnVivo: View {
    var fps: Double = 30
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps)) { _ in
            if let i = CuadroVivo.actual() {
                Image(decorative: i, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Color.s1Pantalla
            }
        }
        .accessibilityHidden(true)
    }
}

/// Una cara dibujada (sin tocar el núcleo), llenando la caja.
struct CaraDibujada: View {
    let expresion: String
    var config: String?
    var pantalla = Pantalla(ancho: 240, alto: 240, redonda: false)
    var fps: Double = 12

    var body: some View {
        PantallaDibujada(config: config, expresion: expresion, pantalla: pantalla, fps: fps)
            .aspectRatio(CGFloat(max(1, pantalla.ancho)) / CGFloat(max(1, pantalla.alto)), contentMode: .fill)
    }
}

/// Lo que se ve en su pantalla cuando no tiene wifi: el ícono buscando, en gris.
struct PantallaSinWifi: View {
    var tamano: CGFloat = 24
    var body: some View {
        ZStack {
            Color.s1Pantalla
            Image(systemName: "wifi.exclamationmark").font(.system(size: tamano, weight: .bold)).foregroundStyle(Color.s1LedSin)
        }
    }
}

/// Su pantalla de 72 (o del tamaño que sea) con lo que corresponde al estado.
struct PantallaS1: View {
    let sesion: SesionS1
    var tamano: TamanoPantalla = .header

    var body: some View {
        MarcoPantalla(tamano: tamano) {
            switch sesion.estado {
            case .sinConexion: PantallaSinWifi(tamano: tamano.lado * 0.3)
            case .conectando: CaraDibujada(expresion: "pensando", config: sesion.modelo.config.paraDibujar, pantalla: sesion.modelo.pantalla)
            default: CaraEnVivo()
            }
        }
        .accessibilityLabel("\(sesion.nombre): \(sesion.estado.texto)")
    }
}

// --- El botón fijo de abajo (APP.md, regla 1) ---

/// Lo que el scroll tiene que dejar libre abajo: el botón (48 + 4 de canto) + 16 + aire.
let AIRE_BOTON_FIJO: CGFloat = 96

/// El botón fijo abajo, con el degradé del fondo detrás.
struct BotonFijo<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.s1Fondo.opacity(0), Color.s1Fondo], startPoint: .top, endPoint: .bottom)
                .frame(height: 32)
                .allowsHitTesting(false)
            contenido
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color.s1Fondo)
        }
    }
}

// --- Los estados de una pantalla con datos (APP.md, regla 9) ---

/// Una barra de esqueleto que late.
struct Esqueleto: View {
    var alto: CGFloat = 16
    var ancho: CGFloat? = nil
    @State private var luz = false

    var body: some View {
        RoundedRectangle(cornerRadius: alto >= 48 ? 12 : 999, style: .continuous)
            .fill(Color.s1Superficie)
            .frame(width: ancho, height: alto)
            .frame(maxWidth: ancho == nil ? .infinity : nil, alignment: .leading)
            .opacity(luz ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: luz)
            .onAppear { luz = true }
            .accessibilityHidden(true)
    }
}

/// Cargando: la S1 pensando y el esqueleto.
struct EstadoCargando: View {
    var renglones = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarcoPantalla(tamano: .header) { CaraDibujada(expresion: "pensando") }
            ForEach(0 ..< renglones, id: \.self) { i in
                HStack(spacing: 12) {
                    Esqueleto(alto: 48, ancho: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        Esqueleto(alto: 14, ancho: i % 2 == 0 ? 160 : 120)
                        Esqueleto(alto: 12, ancho: 90)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando")
    }
}

/// Vacío: su cara contenta y una sola línea.
struct EstadoVacio: View {
    let texto: String
    var expresion = "contento"
    var body: some View {
        VStack(spacing: 16) {
            MarcoPantalla(tamano: .detalle) { CaraDibujada(expresion: expresion) }
            Text(texto).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

/// Error: su cara sorprendida y "Reintentar".
struct EstadoError: View {
    let texto: String
    let reintentar: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            MarcoPantalla(tamano: .header) { CaraDibujada(expresion: "sorpresa") }
            Text(texto).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta).multilineTextAlignment(.center)
            BotonS1("Reintentar", naranja: false, accion: reintentar).frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Sin conexión: su pantalla buscando wifi y el LED gris.
struct EstadoSinConexion: View {
    let nombre: String
    var detalle = ""
    var probar: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            MarcoPantalla(tamano: .detalle) { PantallaSinWifi(tamano: 40) }
            Text("Sin wifi.").font(S1Tipo.titulo).foregroundStyle(Color.s1Tinta)
            ChipEstado(estado: .sinConexion)
            if !detalle.isEmpty { Text(detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2) }
            if let probar { BotonS1("Probar de nuevo", naranja: false, accion: probar).frame(maxWidth: 220) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityLabel("\(nombre) sin conexión")
    }
}
