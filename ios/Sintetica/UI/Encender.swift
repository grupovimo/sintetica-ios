import SwiftUI

/// Para quién es la S1 (se elige al configurarla): cambia cómo se porta.
enum UsoS1: String, CaseIterable, Identifiable {
    case paraMi = "para-mi", cuidado, chicos
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .paraMi: "Para mí"
        case .cuidado: "Cuidado"
        case .chicos: "Chicos"
        }
    }

    var detalle: String {
        switch self {
        case .paraMi: "Timers, listas, agenda y clima."
        case .cuidado: "Pastillas y avisos. La familia se entera."
        case .chicos: "Rutinas y cuentos."
        }
    }

    var foto: String { "foto-\(rawValue)" }

    /// El que se eligió para esta S1 (guardado en el celu).
    static func de(_ id: String) -> UsoS1 { UsoS1(rawValue: UserDefaults.standard.string(forKey: "s1.uso.\(id)") ?? "") ?? .paraMi }
    func guardar(_ id: String) { UserDefaults.standard.set(rawValue, forKey: "s1.uso.\(id)") }

    /// Lo que cambia en su config.
    func aplicar(_ c: inout ConfigDoc) {
        switch self {
        case .paraMi: break
        case .cuidado:
            c.cambiarCuidado { $0.animo = true; $0.extranar = true; $0.extranarDias = 1; $0.resumen = true }
        case .chicos:
            c.ponerHorario(despierta: "08:00", duerme: "21:00")
            c.cambiarCuidado { $0.extranar = false }
        }
    }
}

/// Los caracteres del onboarding (cada uno, un preset).
private let CARACTERES: [(clave: String, nombre: String, dice: String, preset: String, cara: String)] = [
    ("tranqui", "Tranqui", "«Hola. Acá estoy.»", "equilibrado", "neutral"),
    ("charlatana", "Charlatana", "«¡Hola! ¿Hay mate?»", "carinoso", "contento"),
    ("bromista", "Bromista", "«¡Por fin me sacaste de la caja!»", "picaro", "guino"),
]

/// 01–07 · Onboarding: Abrila, el WiFi, su nombre, para quién es, su color y
/// su carácter, la familia y hablale. La barra, el título y la S1 quedan a la
/// misma altura en cada paso; el naranja, siempre en el mismo lugar.
@MainActor
struct EncenderVista: View {
    let sesion: SesionS1
    @Environment(\.dismiss) private var cerrar
    @Environment(\.openURL) private var abrir
    @State private var paso = 1
    @State private var nombre = ""
    @State private var tuNombre = ""
    @State private var uso: UsoS1 = .paraMi
    @State private var color = "#FF6A33"
    @State private var caracter = "charlatana"
    @State private var red = ""
    @State private var clave = ""
    @State private var cerca: ModeloCerca?
    @State private var mensaje = ""
    @State private var ocupado = false
    @State private var telegram: EstadoTelegram?
    @State private var invitacion: Invitacion?
    @State private var error = ""
    @State private var encendiendo = false

    private static let total = 7
    private var modelo: ModeloRobot { sesion.modelo }
    private var quien: String {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Tu S1" : n
    }

    private var titulo: (String, String) {
        switch paso {
        case 1: ("Abrila.", "")
        case 2: ("Conectala", "a tu WiFi.")
        case 3: ("¿Cómo se", "va a llamar?")
        case 4: ("¿Para quién", "es?")
        case 5: ("Su color y", "su carácter.")
        case 6: ("La familia", "se entera.")
        default: ("Hablale.", "")
        }
    }

    private var tieneWifi: Bool { modelo.estado?.wifi == true || (modelo.esNube && modelo.conectado) || cerca?.estado?.wifi == true }

    var body: some View {
        VStack(spacing: 0) {
            arriba
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contenido
                    if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.top, 16) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, AIRE_BOTON_FIJO + 56)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) { abajo }
        }
        .background(FondoConsola())
        .animation(.easeOut(duration: 0.2), value: paso)
        .onAppear(perform: arrancar)
        .task(id: paso) { await alEntrar() }
    }

    // MARK: Lo fijo

    private var arriba: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if paso > 1 {
                    Button { paso -= 1 } label: { IconoS1(.atras).foregroundStyle(Color.s1Tinta).frame(width: 32, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel("Atrás")
                }
                HStack(spacing: 4) {
                    ForEach(1 ... Self.total, id: \.self) { i in
                        Capsule().fill(i <= paso ? Color.s1Inv : Color.s1Linea).frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Paso \(paso) de \(Self.total)")
            }
            .frame(height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(titulo.0)
                Text(titulo.1.isEmpty ? " " : titulo.1)
            }
            .font(.system(size: 36, weight: .bold).width(.expanded)).tracking(-1.2)
            .foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 88, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ZStack {
                if paso == 1 {
                    Image("foto-packaging").resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("La caja de la S1")
                } else {
                    MarcoPantalla(tamano: .detalle) { suPantalla }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(Color.s1Fondo)
    }

    @ViewBuilder private var abajo: some View {
        BotonFijo {
            VStack(spacing: 8) {
                BotonS1(textoPrincipal) { principal() }
                    .disabled(ocupado || encendiendo || (paso == 2 && !tieneWifi && cerca?.cliente != nil && red.trimmingCharacters(in: .whitespaces).isEmpty))
                Button { secundario() } label: {
                    Text(paso == 7 ? " " : "Después").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta2)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .disabled(paso == 7)
                .opacity(paso == 7 ? 0 : 1)
            }
        }
    }

    private var textoPrincipal: String {
        switch paso {
        case 1: return "Ya está enchufada"
        case 2:
            if tieneWifi { return "Seguir" }
            if cerca?.cliente != nil { return ocupado ? "Conectando…" : "Conectar" }
            return ocupado ? "Buscando…" : "Buscarla cerca"
        case 3: return "Listo"
        case 7: return encendiendo ? "Un segundo…" : "Empezar"
        default: return "Seguir"
        }
    }

    /// Lo que se ve en su pantalla en cada paso.
    @ViewBuilder private var suPantalla: some View {
        let config = borrador.paraDibujar
        switch paso {
        case 2:
            if tieneWifi {
                ZStack {
                    Color.s1Pantalla
                    Image(systemName: "wifi").font(.system(size: 44, weight: .bold)).foregroundStyle(Color.s1LedDespierta)
                }
            } else {
                PantallaSinWifi(tamano: 40)
            }
        case 3:
            ZStack {
                Color.s1Pantalla
                Text(quien).font(letraPantalla(30)).foregroundStyle(colorDe(color)).lineLimit(1).minimumScaleFactor(0.4).padding(12)
            }
        case 5:
            CaraDibujada(expresion: CARACTERES.first { $0.clave == caracter }?.cara ?? "contento", config: config, pantalla: modelo.pantalla, fps: 20)
        case 6:
            CaraDibujada(expresion: "enamorado", config: config, pantalla: modelo.pantalla, fps: 20)
        case 7:
            if sesion.estado == .sinConexion {
                PantallaSinWifi(tamano: 40)
            } else if sesion.pensando {
                CaraDibujada(expresion: "pensando", config: config, pantalla: modelo.pantalla, fps: 20)
            } else {
                CaraEnVivo()
            }
        default:
            CaraDibujada(expresion: "contento", config: config, pantalla: modelo.pantalla, fps: 20)
        }
    }

    // MARK: Cada paso

    @ViewBuilder private var contenido: some View {
        switch paso {
        case 1:
            Text("Tirá de la cinta naranja. Después, enchufala con el USB-C.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
        case 2: pasoWifi
        case 3: pasoNombre
        case 4: pasoUso
        case 5: pasoColor
        case 6: pasoFamilia
        default: pasoHablar
        }
    }

    @ViewBuilder private var pasoWifi: some View {
        if tieneWifi {
            HStack(spacing: 12) {
                ChipEstado(estado: .despierta)
                Text("Ya tiene WiFi.").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
            }
        } else if cerca?.cliente != nil {
            VStack(alignment: .leading, spacing: 8) {
                CampoS1(ayuda: "Tu red", texto: $red, teclado: .asciiCapable)
                SecureField("", text: $clave, prompt: Text("La clave").foregroundColor(Color.s1Tinta3))
                    .font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).tint(Color.s1Naranja)
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Campo))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.s1Linea, lineWidth: 1))
            }
        } else {
            Text("Acercá el celu a la S1.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
        }
        if !mensaje.isEmpty { AvisoConsola(texto: mensaje).padding(.top, 12) }
    }

    private var pasoNombre: some View {
        VStack(alignment: .leading, spacing: 12) {
            CampoS1(ayuda: "Su nombre", texto: $nombre)
                .onChange(of: nombre) { _, v in if v.count > 12 { nombre = String(v.prefix(12)) } }
            Flujo(espacio: 8, renglon: 8) {
                ForEach(["Lucho", "Pepa", "Tito", "Coco"], id: \.self) { n in
                    ChipS1(n, elegido: nombre == n) { nombre = n }
                }
            }
            Seccion("¿Y vos?", arriba: 16)
            CampoS1(ayuda: "Tu nombre", texto: $tuNombre)
                .onChange(of: tuNombre) { _, v in let x = cortarBytes(v, 24); if x != v { tuNombre = x } }
        }
    }

    private var pasoUso: some View {
        VStack(spacing: 8) {
            ForEach(UsoS1.allCases) { u in
                TarjetaElegible(elegida: uso == u, accion: { uso = u }) {
                    HStack(spacing: 12) {
                        Image(u.foto).resizable().scaledToFill()
                            .frame(width: 96, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.nombre).font(S1Tipo.seccion)
                            Text(u.detalle).font(S1Tipo.caption).opacity(0.8).lineLimit(2)
                        }
                        .foregroundStyle(uso == u ? Color.s1InvTexto : Color.s1Tinta)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                }
            }
        }
    }

    private var pasoColor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Seccion("Color", arriba: 0)
            HStack(spacing: 12) {
                ForEach(TEMAS_S1, id: \.hex) { t in
                    let si = color == t.hex
                    Button { color = t.hex } label: {
                        Circle().fill(colorDe(t.hex)).frame(width: 40, height: 40)
                            .padding(3)
                            .overlay(Circle().strokeBorder(si ? Color.s1Inv : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.nombre)
                    .accessibilityAddTraits(si ? [.isSelected] : [])
                }
                Spacer()
            }
            .sensoryFeedback(.selection, trigger: color)
            Seccion("Carácter")
            Segmentado(opciones: CARACTERES.map { (clave: $0.clave, nombre: $0.nombre) }, elegida: caracter) { caracter = $0 }
            Text(CARACTERES.first { $0.clave == caracter }?.dice ?? "").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2).padding(.top, 12)
        }
    }

    @ViewBuilder private var pasoFamilia: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Les avisa por Telegram.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            VStack(spacing: 0) {
                FilaIntegracion(logo: "logo-telegram", nombre: tuNombre.isEmpty ? "Vos" : tuNombre, detalle: "Telegram",
                                conectada: telegram?.vinculado == true, ocupado: ocupado) { vincularTelegram() }
                if let inv = invitacion, let u = URL(string: inv.link) {
                    HStack(spacing: 12) {
                        Inicial(nombre: "+")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inv.codigoLindo).font(S1Tipo.seccion.monospacedDigit()).foregroundStyle(Color.s1Tinta)
                            Text("Su código").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                        }
                        Spacer()
                        ShareLink(item: u) { Text("Mandar") }.tecla(chica: true)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                } else {
                    Button { sumarAlguien() } label: {
                        FilaS1(titulo: "Sumar a alguien", flecha: true) { IconoEnCirculo(icono: .sumar) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!Cuenta.compartida.activa)
                }
            }
            .padding(.top, 12)
            Seccion("Así les llega")
            VStack(alignment: .leading, spacing: 8) {
                burbuja("Tomó la pastilla a las 21:02.")
                burbuja("Hoy no contestó «¿cómo estás?». ¿La llamás?")
            }
        }
    }

    private func burbuja(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FichaLogo(imagen: "logo-telegram", tamano: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("La S1 de \(tuNombre.isEmpty ? "vos" : tuNombre)").font(S1Tipo.captionFuerte).foregroundStyle(Color.s1Tinta)
                Text(t).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.s1Superficie))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var pasoHablar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Probá: «¿Llueve hoy?»").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            if sesion.puedeHablar {
                let c = sesion.conversacion
                TeclaHablar(texto: c.estado == .escucha ? "Te escucho" : c.estado == .habla ? "Hablando" : "Mantené para hablar", activa: c.activa,
                            alApretar: { sesion.hablar() }, alSoltar: { sesion.soltarHablar() })
                    .disabled(!modelo.conectado)
            }
            Seccion("Probá con", arriba: 8)
            Flujo(espacio: 8, renglon: 8) {
                ForEach(["¿Llueve hoy?", "Poné un timer de 10", "Contame un chiste", "¿Cómo te llamás?"], id: \.self) { t in
                    ChipS1(t) { Task { await sesion.enviar(t) } }
                }
            }
            .disabled(sesion.pensando || (sesion.charla == nil && !modelo.conectado))
            if sesion.pensando {
                PuntitosPensando()
            } else if let r = sesion.hilo.last, !r.deMi {
                HStack(alignment: .top, spacing: 12) {
                    MarcoPantalla(tamano: .charla) { CaraDibujada(expresion: nombreDibujable(r.expresion), config: borrador.paraDibujar, fps: 8) }
                    Text(r.texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Acciones

    private var borrador: ConfigDoc {
        var c = modelo.config
        c.aV2()
        if !nombre.trimmingCharacters(in: .whitespaces).isEmpty { c.nombre = cortarBytes(quien, 24) }
        c.ponerColor(color)
        if let k = CARACTERES.first(where: { $0.clave == caracter }) { c.ponerPreset(k.preset) }
        return c
    }

    private func arrancar() {
        let c = modelo.config
        nombre = modelo.nombre == "Tu robot" ? "" : String(modelo.nombre.prefix(12))
        tuNombre = c.nombreDueno
        color = TEMAS_S1.contains { $0.hex == c.colorOjos } ? c.colorOjos : "#FF6A33"
        uso = UsoS1.de(modelo.id)
        if c.tienePreset, let k = CARACTERES.first(where: { $0.preset == c.preset }) { caracter = k.clave }
        if cerca == nil { cerca = ModeloCerca(id: modelo.id, cliente: modelo.esBle ? modelo.cliente : nil) }
    }

    private func alEntrar() async {
        error = ""
        mensaje = ""
        switch paso {
        case 6:
            if Cuenta.compartida.activa { telegram = try? await Cuenta.compartida.api.telegram() }
        case 7:
            if let e = await modelo.guardarAhora(borrador) { error = e }
        default:
            break
        }
    }

    private func principal() {
        switch paso {
        case 2:
            if tieneWifi { paso = 3; return }
            guard let cerca else { paso = 3; return }
            ocupado = true
            Task {
                defer { ocupado = false }
                if cerca.cliente == nil {
                    await cerca.conectar()
                    mensaje = cerca.cliente == nil ? cerca.mensaje : ""
                    return
                }
                await cerca.configurarRed(red.trimmingCharacters(in: .whitespaces), clave)
                if Cuenta.compartida.activa, cerca.estado?.redConfigurada == true, !modelo.esNube { await cerca.sumarACuenta() }
                mensaje = cerca.mensaje
                if cerca.estado?.wifi == true || cerca.mensaje.hasPrefix("Listo") { paso = 3 }
            }
        case 3:
            paso = 4
        case 7:
            terminar()
        default:
            paso += 1
        }
    }

    private func secundario() {
        if paso < 7 { paso += 1 }
    }

    private func vincularTelegram() {
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                if let e = try await Cuenta.compartida.api.vincularTelegram(), let u = URL(string: e) { abrir(u) }
                for _ in 0 ..< 40 {
                    try? await Task.sleep(for: .seconds(3))
                    if paso != 6 { return }
                    if let t = try? await Cuenta.compartida.api.telegram() { telegram = t; if t.vinculado { return } }
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func sumarAlguien() {
        Task {
            do { invitacion = try await Cuenta.compartida.api.invitarAmigo() } catch { self.error = error.localizedDescription }
        }
    }

    private func terminar() {
        encendiendo = true
        error = ""
        Task {
            var c = borrador
            c.ponerNombreDueno(tuNombre)
            uso.aplicar(&c)
            if caracter == "charlatana" { c.ponerFrecuenciaHabla(0.8) }
            uso.guardar(modelo.id)
            if !nombre.trimmingCharacters(in: .whitespaces).isEmpty, modelo.esNube, quien != modelo.nombre {
                if let e = await modelo.ponerApodo(quien) { error = e; encendiendo = false; return }
            }
            if let e = await modelo.guardarAhora(c) {
                error = e
                encendiendo = false
                return
            }
            modelo.marcarEncendido()
            encendiendo = false
            cerrar()
        }
    }
}
