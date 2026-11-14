import SwiftUI

/// 08 · Inicio: la S1 grande (el render con su pantalla viva), el saludo, el
/// estado, las cuatro teclas, "Mantené para hablar", su color y lo de hoy.
@MainActor
struct InicioS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var mensaje = ""

    /// Los colores de sus ojos que se eligen desde el Inicio (de COLORES_OJOS).
    private static let colores = ["#FF6A33", "#4ADE80", "#3DE0FF", "#FF5FA2"]

    var body: some View {
        let modelo = sesion.modelo
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroS1(sesion: sesion)
                    .padding(.horizontal, -20)
                switch modelo.fase {
                case .conectando:
                    saludo
                    EstadoCargando(renglones: 2).padding(.top, 24)
                case let .error(m, revincular):
                    saludo
                    falla(m, revincular)
                case .lista:
                    saludo
                    contenido
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }

    private var saludo: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.textoSaludo() + ",")
                Text(nombreDueno + ".")
            }
            .font(S1Tipo.display).tracking(-1.76).foregroundStyle(Color.s1Tinta)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityElement(children: .combine)
            ChipEstado(estado: sesion.estado)
        }
        .padding(.top, 16)
    }

    private var nombreDueno: String {
        let n = sesion.modelo.config.nombreDueno.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? sesion.nombre : n
    }

    static func textoSaludo(_ d: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: d)
        if h >= 6 && h < 13 { return "Buen día" }
        if h >= 13 && h < 20 { return "Buenas tardes" }
        return "Buenas noches"
    }

    @ViewBuilder private func falla(_ m: String, _ revincular: Bool) -> some View {
        if revincular {
            EstadoError(texto: m) {
                Vinculados.compartidos.olvidar(sesion.id)
                ir(.misS1)
            }
        } else {
            EstadoSinConexion(nombre: sesion.nombre, detalle: m) { Task { await sesion.reintentar() } }
        }
    }

    @ViewBuilder private var contenido: some View {
        let modelo = sesion.modelo
        let conectado = modelo.conectado
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            TeclaAtajo(icono: .timer, nombre: "Timer") { ir(.charla("Poné un timer de 10 minutos")) }
            TeclaAtajo(icono: .lista, nombre: "Lista") { ir(.modulo(.listas)) }
            TeclaAtajo(icono: .recordar, nombre: "Recordar") { ir(.modulo(.recordatorios)) }
            TeclaAtajo(icono: .cobrar, nombre: "Cobrar") { ir(.modulo(.avisos)) }
        }
        .padding(.top, 16)
        hablar(conectado).padding(.top, 12)
        if !sesion.conversacion.aviso.isEmpty { AvisoConsola(texto: sesion.conversacion.aviso, error: true).padding(.top, 8) }
        if !mensaje.isEmpty { AvisoConsola(texto: mensaje).padding(.top, 8) }
        suColor.padding(.top, 24)
        Seccion("De un toque")
        Flujo(espacio: 8, renglon: 8) {
            ChipS1("Acariciar") { hacer(["evento": "caricia"], "Le gustó") }
            ChipS1("Llamarla") { hacer(["evento": "nombre"], "Te escuchó") }
            ChipS1("Cosquillas") { hacer(["evento": "muchos-toques"], "Se rió") }
            ChipS1("Jugar") { ir(.modulo(.jugar)) }
            if modelo.caraFija {
                ChipS1("Soltar la cara") { hacer(["expresion": ""], "Vuelve a ser ella") }
            }
        }
        .disabled(!conectado)
        if let s = modelo.suena {
            SuenaAhora(suena: s, claro: true).padding(.top, 24)
        }
        hoyEnSuPantalla
    }

    /// La tecla de hablar: con la voz en tiempo real, se aprieta y te escucha;
    /// sin ella, lleva a la Charla.
    private func hablar(_ conectado: Bool) -> some View {
        let c = sesion.conversacion
        let texto: String
        if !sesion.puedeHablar {
            texto = "Hablale"
        } else {
            switch c.estado {
            case .quieto: texto = "Mantené para hablar"
            case .conectando: texto = "Un segundo…"
            case .escucha: texto = "Te escucho"
            case .habla: texto = "Hablando"
            }
        }
        return TeclaHablar(texto: texto, activa: c.activa) {
            if sesion.puedeHablar { sesion.hablar() } else { ir(.charla("")) }
        }
        .disabled(!conectado && sesion.puedeHablar)
        .onDisappear { if sesion.conversacion.activa { sesion.conversacion.cortar() } }
    }

    private var suColor: some View {
        let actual = sesion.modelo.config.colorOjos
        return HStack {
            Text("Su color").font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
            Spacer()
            HStack(spacing: 8) {
                ForEach(Self.colores, id: \.self) { hex in
                    let si = actual == hex
                    Button { sesion.modelo.cambiar { $0.ponerColor(hex) } } label: {
                        HStack(spacing: 3) {
                            Capsule().fill(colorDe(hex)).frame(width: 4, height: 11)
                            Capsule().fill(colorDe(hex)).frame(width: 4, height: 11)
                        }
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.s1Pantalla))
                        .padding(3)
                        .overlay(Circle().strokeBorder(si ? Color.s1Inv : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(COLORES_OJOS.first { $0.hex == hex }?.nombre ?? hex)
                    .accessibilityAddTraits(si ? [.isSelected] : [])
                }
            }
        }
        .frame(minHeight: 36)
    }

    /// Lo próximo que va a mostrar: los recordatorios de hoy y el despertador.
    @ViewBuilder private var hoyEnSuPantalla: some View {
        let proximos = ProximosS1.de(sesion.modelo.config, limite: 3)
        if !proximos.isEmpty {
            Seccion("Hoy en su pantalla")
            VStack(spacing: 0) {
                ForEach(proximos) { p in
                    Button { ir(.modulo(p.modulo)) } label: {
                        FilaS1(titulo: p.titulo, detalle: p.detalle, valor: p.hora) { IconoEnCirculo(icono: p.icono) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func hacer(_ c: [String: String], _ texto: String) {
        Task {
            let e = await sesion.modelo.comando(c)
            mensaje = e ?? texto
            try? await Task.sleep(for: .seconds(2.5))
            mensaje = ""
        }
    }
}

/// Lo que viene hoy (recordatorios prendidos que tocan hoy y el despertador),
/// ordenado por hora, desde ahora.
struct ProximosS1: Identifiable, Equatable {
    let id: String
    let titulo: String
    let detalle: String
    let hora: String
    let icono: Icono
    let modulo: Modulo

    static func de(_ c: ConfigDoc, limite: Int, ahora: Date = Date(), soloDesdeAhora: Bool = true) -> [ProximosS1] {
        let cal = Calendar.current
        let minutos = cal.component(.hour, from: ahora) * 60 + cal.component(.minute, from: ahora)
        let letra = letraDelDia(ahora)
        var l: [ProximosS1] = []
        for (i, r) in c.recordatorios.enumerated() where r.prendido && (r.dias.isEmpty || r.tiene(letra)) {
            if soloDesdeAhora, aMinutos(r.hora) < minutos { continue }
            l.append(ProximosS1(id: "r\(i)", titulo: r.texto, detalle: "Recordatorio", hora: r.hora, icono: .recordar, modulo: .recordatorios))
        }
        if let d = c.despertador, d.activo, d.dias.isEmpty || d.dias.contains(letra) {
            if !soloDesdeAhora || aMinutos(d.hora) >= minutos {
                l.append(ProximosS1(id: "despertador", titulo: d.texto.isEmpty ? "Despertador" : d.texto, detalle: "Despertador",
                                    hora: d.hora, icono: .sistema("alarm"), modulo: .dia))
            }
        }
        return Array(l.sorted { $0.hora < $1.hora }.prefix(limite))
    }

    /// La letra del día como en los recordatorios (DIAS_SEMANA).
    static func letraDelDia(_ d: Date) -> String {
        // Calendar: 1 = domingo. DIAS_SEMANA va de lunes a domingo.
        let w = Calendar.current.component(.weekday, from: d)
        let i = (w + 5) % 7
        return i < DIAS_SEMANA.count ? DIAS_SEMANA[i].letra : ""
    }
}

/// El render de la S1 con su pantalla viva encastrada (como S.hero en
/// s1-pantalla.js): de día la foto clara, de noche la oscura. El broche (de
/// pantalla redonda) sigue con su foto de siempre.
struct HeroS1: View {
    let sesion: SesionS1
    var alto: CGFloat = 400
    @Environment(\.colorScheme) private var esquema

    private struct Geo {
        let imagen: String
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat
        /// Dónde se corta la esquina de bronce (abajo a la derecha).
        let corteAlto: CGFloat, corteAncho: CGFloat
    }

    private static let geoDia = Geo(imagen: "s1-dia", x: 0.3357, y: 0.1696, w: 0.3286, h: 0.3232, r: 0.016, corteAlto: 0.80, corteAncho: 0.795)
    private static let geoNoche = Geo(imagen: "s1-noche", x: 0.2855, y: 0.1758, w: 0.3065, h: 0.3194, r: 0.0226, corteAlto: 0.82, corteAncho: 0.78)

    var body: some View {
        let modelo = sesion.modelo
        GeometryReader { g in
            if modelo.producto.redonda {
                Producto(modelo: modelo.producto, apagado: !modelo.conectado, radio: 0) {
                    pantalla
                }
                .frame(width: min(g.size.width, alto * 0.8))
                .frame(width: g.size.width, height: alto)
            } else {
                render(g.size)
            }
        }
        .frame(height: alto)
        .background(fondo)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sesion.nombre)
    }

    private var noche: Bool { esquema == .dark }

    private var fondo: some View {
        RadialGradient(colors: noche ? [Color(hex: 0x46281A), Color(hex: 0x151311)] : [Color.white, Color(hex: 0xF7F4EF), Color(hex: 0xECE6DC)],
                       center: UnitPoint(x: 0.5, y: noche ? 0.55 : 0.46), startRadius: 0, endRadius: 300)
    }

    private func render(_ t: CGSize) -> some View {
        let geo = noche ? Self.geoNoche : Self.geoDia
        let k = t.width / 393
        let ancho: CGFloat = 600 * k
        let altoImagen: CGFloat = ancho * 688 / 1100
        let cx = t.width / 2, cy = 226 * alto / 400
        let izq = cx - ancho * (geo.x + geo.w / 2)
        let arriba = cy - ancho * (geo.y + geo.h / 2)
        let sw = ancho * geo.w, sh = ancho * geo.h
        return ZStack(alignment: .topLeading) {
            Ellipse().fill(Color.black.opacity(noche ? 0.5 : 0.32)).frame(width: 250 * k, height: 30 * k).blur(radius: 10)
                .offset(x: cx - 125 * k, y: 346 * alto / 400)
            Image(geo.imagen).resizable().interpolation(.high)
                .frame(width: ancho, height: altoImagen)
                .mask { mascara(ancho: ancho, alto: altoImagen) }
                .offset(x: izq, y: arriba)
                .saturation(sesion.estado == .sinConexion ? 0.4 : 1)
                .accessibilityHidden(true)
            pantalla
                .frame(width: sw, height: sh)
                .clipShape(EsquinaCortada(alto: geo.corteAlto, ancho: geo.corteAncho))
                .clipShape(RoundedRectangle(cornerRadius: ancho * geo.r, style: .continuous))
                .offset(x: izq + ancho * geo.x, y: arriba + ancho * geo.y)
        }
        .frame(width: t.width, height: alto, alignment: .topLeading)
    }

    /// De día, el recorte del cubo; de noche, un óvalo que se desvanece.
    @ViewBuilder private func mascara(ancho: CGFloat, alto: CGFloat) -> some View {
        if noche {
            RadialGradient(stops: [.init(color: .black, location: 0.62), .init(color: .clear, location: 1)],
                           center: UnitPoint(x: 0.47, y: 0.54), startRadius: 0, endRadius: ancho * 0.44)
        } else {
            let kx = ancho / 1100, ky = alto / 688
            RoundedRectangle(cornerRadius: 58 * kx, style: .continuous)
                .frame(width: 440 * kx, height: 482 * ky)
                .blur(radius: 3 * kx)
                .offset(x: 336 * kx + 220 * kx - ancho / 2, y: 124 * ky + 241 * ky - alto / 2)
        }
    }

    /// Su pantalla: viva, o buscando wifi si no tiene conexión. Al tocarla, la siente.
    @ViewBuilder private var pantalla: some View {
        if sesion.estado == .sinConexion {
            PantallaSinWifi(tamano: 36)
        } else {
            CaraEnVivo()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in sesion.modelo.tocar(true) }
                    .onEnded { _ in sesion.modelo.tocar(false) })
                .accessibilityLabel("Su pantalla")
        }
    }
}

/// El rectángulo de su pantalla con la esquina de bronce cortada.
struct EsquinaCortada: Shape {
    let alto: CGFloat
    let ancho: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * alto))
        p.addLine(to: CGPoint(x: r.minX + r.width * ancho, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
