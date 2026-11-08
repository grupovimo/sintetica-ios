import SwiftUI

/// Los diez módulos de la consola.
enum Modulo: String, CaseIterable, Identifiable {
    case caracter, cara, imagenes, dia, recordatorios, modos, reflejos, integraciones, voz, ajustes
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .caracter: "Carácter"
        case .cara: "Cara"
        case .imagenes: "Imágenes"
        case .dia: "Su día"
        case .recordatorios: "Recordatorios"
        case .modos: "Modos"
        case .reflejos: "Reflejos"
        case .integraciones: "Integraciones"
        case .voz: "Voz"
        case .ajustes: "Ajustes"
        }
    }

    var icono: String {
        switch self {
        case .caracter: "dial.medium"
        case .cara: "eyes"
        case .imagenes: "photo.stack"
        case .dia: "sun.horizon"
        case .recordatorios: "alarm"
        case .modos: "square.grid.2x2"
        case .reflejos: "cable.connector"
        case .integraciones: "point.3.connected.trianglepath.dotted"
        case .voz: "waveform"
        case .ajustes: "gearshape"
        }
    }

    /// Voz: solo si el modelo tiene micrófono o parlante.
    func bloqueado(_ m: ModeloProducto) -> Bool { self == .voz && !m.tiene(.microfono) && !m.tiene(.parlante) }
}

/// La consola de un robot: arriba él (la foto real con su cara en vivo), abajo
/// una placa con un teclado de módulos. Todo se guarda solo. Como
/// web/src/routes/robots/[id]/+page.svelte.
@MainActor
struct ConsolaVista: View {
    @Binding var ruta: [Ruta]
    @State private var modelo: ModeloRobot
    @State private var actual: Modulo = .caracter
    @State private var mensaje = ""
    @State private var laboratorio = false
    @State private var encender = false
    @State private var cerca = false

    init(id: String, ruta: Binding<[Ruta]>) {
        _ruta = ruta
        _modelo = State(initialValue: ModeloRobot(id: id))
    }

    var body: some View {
        Group {
            switch modelo.fase {
            case .conectando: cargando
            case let .error(m, revincular): falla(m, revincular)
            case .lista: consola
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FondoConsola())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await modelo.abrir()
            if modelo.fase == .lista, modelo.debeEncender { encender = true }
        }
        .onDisappear { modelo.cerrar() }
        .fullScreenCover(isPresented: $laboratorio) { LaboratorioVista(modelo: modelo) }
        .fullScreenCover(isPresented: $encender) { EncenderVista(modelo: modelo) }
        .sheet(isPresented: $cerca) { CercaVista(modelo: modelo) }
    }

    private var volver: some View {
        Button { ruta = [] } label: { Label("Mis robots", systemImage: "chevron.left") }.tecla(.negra, chica: true)
    }

    private var cargando: some View {
        VStack(alignment: .leading, spacing: 24) {
            volver
            Grabado(modelo.esDemo ? "De prueba" : "Buscando…", color: .brasa)
            Titular(modelo.esDemo ? "Despertando" : "Conectando")
            ProgressView().tint(Color.brasa)
            Spacer()
        }
        .padding(16)
    }

    private func falla(_ m: String, _ revincular: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            volver
            Titular("Sin conexión")
            AvisoConsola(texto: m, error: true)
            if revincular {
                Button { Vinculados.compartidos.olvidar(modelo.id); ruta = [.escanear] } label: { Text("Vincular de nuevo") }.tecla(.naranja, ancha: true)
            } else {
                Button { Task { await modelo.abrir() } } label: { Label("Reintentar", systemImage: "arrow.clockwise") }.tecla(.naranja, ancha: true)
            }
            Spacer()
        }
        .padding(16)
    }

    private var consola: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                barra
                if let a = modelo.aviso { AvisoDelRobot(aviso: a) { modelo.aviso = nil } }
                Heroe(modelo: modelo, mensaje: $mensaje)
                tablero
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: modelo.aviso)
    }

    private var barra: some View {
        HStack {
            volver
            Spacer()
            HStack(spacing: 8) {
                Led(estado: ledGuardado)
                Text(modelo.textoGuardado.uppercased()).font(Tipos.marca(10, .heavy)).tracking(1)
                    .foregroundStyle(modelo.guardado == .error ? Color.rojo : Color.gris).lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.top, 8)
    }

    private var ledGuardado: EstadoLed {
        switch modelo.guardado {
        case .guardando: .on
        case .guardado: .verde
        case .error: .rojo
        case .listo: .apagado
        }
    }

    private var tablero: some View {
        PlacaNaranja(relleno: 14, radio: 28) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Modulo.allCases) { m in
                    TeclaModulo(modulo: m, elegido: actual == m, bloqueado: m.bloqueado(modelo.producto)) { actual = m }
                }
            }
            if modelo.guardado == .error, !modelo.errorGuardado.isEmpty { AvisoConsola(texto: modelo.errorGuardado, error: true) }
            panel.id(actual)
        }
    }

    @ViewBuilder private var panel: some View {
        switch actual {
        case .caracter: ModCaracter(modelo: modelo)
        case .cara: ModCara(modelo: modelo)
        case .imagenes: ModImagenes(modelo: modelo)
        case .dia: ModDia(modelo: modelo)
        case .recordatorios: ModRecordatorios(modelo: modelo)
        case .modos: ModModos(modelo: modelo)
        case .reflejos: ModReflejos(modelo: modelo)
        case .integraciones: ModIntegraciones(modelo: modelo)
        case .voz: ModVoz(modelo: modelo)
        case .ajustes: ModAjustes(modelo: modelo, laboratorio: { laboratorio = true }, cerca: { cerca = true }, volver: { ruta = [] })
        }
    }
}

/// Una tecla del teclado de módulos, con su LED.
private struct TeclaModulo: View {
    let modulo: Modulo
    let elegido: Bool
    let bloqueado: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: modulo.icono).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    if bloqueado {
                        Circle().strokeBorder(lineWidth: 1.5).frame(width: 8, height: 8).opacity(0.5)
                    } else {
                        Circle().fill(elegido ? Color.led : Color.grisClaro).frame(width: 8, height: 8)
                            .shadow(color: elegido ? Color.led : .clear, radius: 5)
                    }
                }
                Text(modulo.nombre.uppercased()).font(Tipos.angosta(10, .black)).lineLimit(1).minimumScaleFactor(0.55)
            }
            .foregroundStyle(elegido ? Color.papel : Color.tinta)
            .padding(.horizontal, 8).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        }
        .buttonStyle(EstiloTeclaModulo(elegido: elegido))
        .accessibilityLabel(modulo.nombre)
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: elegido)
    }
}

/// Las teclas grandes (módulos, modos, solapas): blancas, y negras hundidas si están elegidas.
struct EstiloTeclaModulo: ButtonStyle {
    let elegido: Bool
    func makeBody(configuration: Configuration) -> some View {
        let abajo = elegido || configuration.isPressed
        let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let colores: [Color] = elegido ? [Color(hex: 0x2A2622), Color(hex: 0x151310)] : [Color(hex: 0xFBF9F5), Color(hex: 0xE6E0D6)]
        return configuration.label
            .background(forma.fill(LinearGradient(colors: colores, startPoint: .top, endPoint: .bottom)))
            .background(forma.fill(elegido ? Color.black : Color(hex: 0x8F887C)).offset(y: abajo ? 1 : 5))
            .shadow(color: Color(hex: 0x501400).opacity(abajo ? 0.2 : 0.5), radius: abajo ? 1 : 6, y: abajo ? 1 : 8)
            .offset(y: abajo ? 4 : 0)
            .padding(.bottom, 5)
            .animation(.easeOut(duration: 0.08), value: abajo)
    }
}

/// Lo que el robot acaba de avisar solo (un recordatorio, el fin de un pomodoro, tu IA).
struct AvisoDelRobot: View {
    let aviso: ModeloRobot.Aviso
    let cerrar: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: aviso.icono).font(.system(size: 22, weight: .bold))
            Text(aviso.texto.uppercased()).font(Tipos.marca(19, .black)).lineLimit(2).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Button("OK", action: cerrar).tecla(.negra, chica: true)
        }
        .foregroundStyle(Color.tinta)
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color.brasa, Color(hex: 0xF2541A)], startPoint: .top, endPoint: .bottom)))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x9A3209)).offset(y: 6))
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.warning, trigger: aviso)
        .accessibilityElement(children: .combine)
    }
}

/// El héroe: la foto con la cara en vivo, su nombre, cómo está, lo que trae y
/// las acciones rápidas.
private struct Heroe: View {
    let modelo: ModeloRobot
    @Binding var mensaje: String

    var body: some View {
        let m = modelo.producto
        let conectado = modelo.conectado
        VStack(alignment: .leading, spacing: 18) {
            Producto(modelo: m, apagado: !conectado, etiqueta: conectado ? "\(modelo.nombre) · en vivo" : "Así se ve") {
                PantallaNucleo { modelo.tocar($0) }
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Led(estado: conectado ? .verde : .apagado)
                Grabado(estadoTexto(m), color: .grisClaro)
            }
            Titular(modelo.nombre)
            Text(animoTexto).font(Tipos.marca(17, .semibold)).foregroundStyle(Color.hueso)
            capacidades(m)
            acciones(conectado)
            if !mensaje.isEmpty { AvisoConsola(texto: mensaje) }
        }
    }

    private func estadoTexto(_ m: ModeloProducto) -> String {
        let quien = "\(m.nombre) \(numeroDe(modelo.id))"
        if modelo.esDemo { return "De prueba · \(m.nombre)" }
        if modelo.esBle { return "Cerca · \(quien)" }
        return modelo.conectado ? "Conectado · \(quien)" : "Visto \(hace(modelo.robot?.ultimaConexion)) · \(quien)"
    }

    private var animoTexto: String {
        let a = animoDe(modelo.estado, conectado: modelo.conectado)
        if let b = modelo.estado?.bateria { return "\(a) · \(b)%" }
        return a
    }

    private func capacidades(_ m: ModeloProducto) -> some View {
        Flujo(espacio: 8, renglon: 8) {
            ForEach(Capacidad.allCases, id: \.self) { c in
                let si = m.tiene(c)
                HStack(spacing: 7) {
                    Led(estado: si ? .on : .apagado, tamano: 7)
                    Image(systemName: c.icono).font(.system(size: 11, weight: .semibold))
                    Text(c.nombre.uppercased()).font(Tipos.marca(10, .heavy)).tracking(0.8)
                }
                .foregroundStyle(si ? Color.hueso : Color(hex: 0x5A524A))
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(si ? Color.chapa : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(si ? Color.clear : Color(hex: 0x2C2925), lineWidth: 1))
                .accessibilityLabel("\(c.nombre): \(si ? "sí" : "no")")
            }
        }
    }

    private func acciones(_ conectado: Bool) -> some View {
        Flujo(espacio: 10, renglon: 6) {
            Button { hacer(["evento": "caricia"], "Le gustó") } label: { Label("Acariciar", systemImage: "hand.raised.fill") }.tecla()
            Button { hacer(["evento": "nombre"], "Te escuchó") } label: { Label("Llamarlo", systemImage: "megaphone.fill") }.tecla()
            Button { hacer(["evento": "muchos-toques"], "Se rió") } label: { Label("Cosquillas", systemImage: "sparkles") }.tecla(.naranja)
            if modelo.caraFija {
                Button { hacer(["expresion": ""], "Vuelve a ser él") } label: { Text("Soltar la cara") }.tecla(.negra)
            }
        }
        .disabled(!conectado)
    }

    private func hacer(_ c: [String: String], _ texto: String) {
        Task {
            let e = await modelo.comando(c)
            mensaje = e ?? texto
            try? await Task.sleep(for: .seconds(2.5))
            mensaje = ""
        }
    }
}
