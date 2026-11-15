import SwiftUI

// Conversaciones: lo que graba el broche (o el celu), pasado a texto y
// resumido por la nube. La lista, "Grabar" abajo y el detalle de cada una.

/// "Hoy 14:05" o "12 nov 09:30".
func fechaConversacion(_ d: Date?) -> String {
    guard let d else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_AR")
    let hoy = Calendar.current.isDateInToday(d)
    f.setLocalizedDateFormatFromTemplate(hoy ? "HH:mm" : "d MMM HH:mm")
    return hoy ? "Hoy " + f.string(from: d) : f.string(from: d)
}

/// La fecha corta y lo que dura.
func cuandoConversacion(_ c: ConversacionGrabada) -> String {
    let f = fechaConversacion(c.empezo)
    guard c.segundos > 0 else { return f }
    return f.isEmpty ? mmss(c.segundos) : f + " · " + mmss(c.segundos)
}

/// El estado de una conversación: un chip de 28 con su LED.
private struct ChipConversacion: View {
    let texto: String
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(texto).font(S1Tipo.captionFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(height: 28)
        .overlay(Capsule().strokeBorder(Color.s1Linea, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Conversaciones: la lista y el botón fijo "Grabar" (pasa a "Terminar · 02:31").
@MainActor
struct ConversacionesS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var lista: [ConversacionGrabada] = []
    @State private var fase: Fase = .cargando
    @State private var abierta: ConversacionGrabada?
    @State private var oyente: UUID?
    @State private var error = ""
    @State private var reintentando: Set<Int> = []

    private enum Fase { case cargando, lista, error }
    private var grabador: GrabadorConversacion { sesion.grabador }
    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Conversaciones", sesion: sesion, atras: { ir(.cerrarModulo) })
            if !Cuenta.compartida.activa {
                ScrollView { SoloNube().padding(20) }
            } else {
                CuerpoConBoton { contenido } boton: { botonGrabar }
            }
        }
        .background(FondoConsola())
        .task {
            await cargar()
            // Por si no llegan los eventos en vivo: mientras alguna se procesa.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if lista.contains(where: { $0.enCurso }) { await cargar() }
            }
        }
        .onAppear { escuchar() }
        .onDisappear { dejar() }
        .onChange(of: grabador.terminadas) { _, _ in Task { await cargar() } }
        .onChange(of: grabador.estado) { _, e in
            if e == .grabando { Task { await cargar() } }
        }
        .navigationDestination(item: $abierta) { c in
            DetalleConversacionS1(sesion: sesion, conversacion: c) { Task { await cargar() } }
        }
    }

    @ViewBuilder private var contenido: some View {
        if grabador.grabando || grabador.estado == .terminando {
            grabando
        }
        if !grabador.aviso.isEmpty { AvisoConsola(texto: grabador.aviso, error: true).padding(.bottom, 12) }
        if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.bottom, 12) }
        switch fase {
        case .cargando:
            EstadoCargando(renglones: 3)
        case .error:
            EstadoError(texto: "No pude verlas.") { Task { await cargar() } }
        case .lista:
            if lista.isEmpty {
                EstadoVacio(texto: "Ninguna todavía.", expresion: "pensando")
            } else {
                VStack(spacing: 0) {
                    ForEach(lista) { c in fila(c) }
                }
            }
        }
    }

    /// Lo que se está grabando ahora: el LED y el tiempo.
    private var grabando: some View {
        TarjetaS1 {
            HStack(spacing: 8) {
                Circle().fill(Color.s1Error).frame(width: 10, height: 10)
                Text(grabador.grabando ? "Grabando" : "Subiendo…").font(S1Tipo.captionFuerte).foregroundStyle(Color.s1Tinta)
                Spacer(minLength: 0)
            }
            Text(mmss(grabador.segundos)).font(.system(size: 44, weight: .bold).monospacedDigit()).foregroundStyle(Color.s1Tinta)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    private func fila(_ c: ConversacionGrabada) -> some View {
        HStack(spacing: 12) {
            Button { abierta = c } label: {
                HStack(spacing: 12) {
                    IconoEnCirculo(icono: c.lista ? .sistema("text.bubble") : .sistema("mic"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.titulo.isEmpty ? "Conversación" : c.titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                        Text(cuandoConversacion(c)).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            chip(c)
            if c.lista { IconoS1(.adelante, tamano: 20).foregroundStyle(Color.s1Tinta2).accessibilityHidden(true) }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
    }

    @ViewBuilder private func chip(_ c: ConversacionGrabada) -> some View {
        switch c.estado {
        case "grabando":
            ChipConversacion(texto: "Grabando", color: .s1Error)
        case "procesando":
            ChipConversacion(texto: "Pasando a texto…", color: .s1LedDurmiendo)
        case "fallo":
            Button { reintentar(c) } label: {
                ChipConversacion(texto: reintentando.contains(c.id) ? "Reintentando…" : "Falló · Reintentar", color: .s1Error)
            }
            .buttonStyle(.plain)
            .disabled(reintentando.contains(c.id))
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var botonGrabar: some View {
        switch grabador.estado {
        case .quieto:
            BotonS1("Grabar") { grabar() }
        case .arrancando:
            BotonS1("Grabar") {}.disabled(true)
        case .grabando:
            BotonS1("Terminar · \(mmss(grabador.segundos))") { Task { await grabador.terminar() } }
        case .terminando:
            BotonS1("Subiendo…") {}.disabled(true)
        }
    }

    private func grabar() {
        error = ""
        // La voz en tiempo real usa el mismo micrófono.
        if sesion.conversacion.activa { sesion.conversacion.cortar() }
        Task { await grabador.grabar() }
    }

    private func cargar() async {
        guard Cuenta.compartida.activa else { return }
        do {
            lista = try await api.conversaciones()
            fase = .lista
        } catch {
            if fase != .lista { fase = .error }
        }
    }

    private func reintentar(_ c: ConversacionGrabada) {
        reintentando.insert(c.id)
        Task {
            defer { reintentando.remove(c.id) }
            do {
                try await api.reintentarConversacion(c.id)
                error = ""
            } catch let e as ErrorApi {
                error = e.mensaje
            } catch {
                self.error = "No pude"
            }
            await cargar()
        }
    }

    private func escuchar() {
        guard oyente == nil, Cuenta.compartida.activa else { return }
        oyente = EnVivo.compartido.escuchar { e in
            guard e.tipo == "grabacion" else { return }
            Task { await cargar() }
        }
    }

    private func dejar() {
        if let o = oyente { EnVivo.compartido.dejar(o) }
        oyente = nil
    }
}

/// Una conversación: título, resumen, puntos, pendientes y la transcripción
/// plegada. Compartir el resumen y borrarla.
@MainActor
struct DetalleConversacionS1: View {
    let sesion: SesionS1
    let conversacion: ConversacionGrabada
    let alCambiar: () -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var completa: ConversacionGrabada?
    @State private var verTexto = false
    @State private var hechos: Set<Int> = []
    @State private var confirmar = false
    @State private var borrando = false
    @State private var reintentando = false
    @State private var error = ""
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        let c = completa ?? conversacion
        VStack(spacing: 0) {
            HeaderS1(titulo: "Conversación", sesion: sesion, atras: { cerrar() })
            CuerpoConBoton { contenido(c) } boton: { boton(c) }
        }
        .background(FondoConsola())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task { await cargar() }
        .onAppear { escuchar() }
        .onDisappear { dejar() }
        .confirmationDialog("¿Seguro?", isPresented: $confirmar, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { borrar() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    @ViewBuilder private func contenido(_ c: ConversacionGrabada) -> some View {
        Text(c.titulo.isEmpty ? "Conversación" : c.titulo).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        Text(cuandoConversacion(c)).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).padding(.top, 4)
        if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.top, 12) }
        if c.lista {
            lista(c)
        } else if c.fallo {
            EstadoVacio(texto: "Falló.", expresion: "triste")
            if !c.detalle.isEmpty {
                Text(c.detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            BotonS1("Borrar", naranja: false) { confirmar = true }.disabled(borrando).padding(.top, 24)
        } else {
            EstadoVacio(texto: c.estado == "grabando" ? "Grabando…" : "Pasando a texto…", expresion: "pensando")
        }
    }

    @ViewBuilder private func lista(_ c: ConversacionGrabada) -> some View {
        if !c.resumen.isEmpty {
            Text(c.resumen).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 16)
        }
        if !c.puntos.isEmpty {
            Seccion("Puntos")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(c.puntos.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta2)
                        Text(p).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if !c.pendientes.isEmpty {
            Seccion("Pendientes")
            VStack(spacing: 0) {
                ForEach(Array(c.pendientes.enumerated()), id: \.offset) { i, p in pendiente(i, p) }
            }
        }
        transcripcion(c)
        BotonS1(borrando ? "Borrando…" : "Borrar", naranja: false) { confirmar = true }
            .disabled(borrando)
            .padding(.top, 32)
    }

    /// Un pendiente con su casilla (solo para la vista: no se guarda).
    private func pendiente(_ i: Int, _ texto: String) -> some View {
        let hecho = hechos.contains(i)
        return Button {
            if hecho { hechos.remove(i) } else { hechos.insert(i) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: hecho ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(hecho ? Color.s1Acento : Color.s1Tinta2)
                Text(texto).font(S1Tipo.cuerpo).foregroundStyle(hecho ? Color.s1Tinta2 : Color.s1Tinta)
                    .strikethrough(hecho)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: hecho)
        .accessibilityAddTraits(hecho ? [.isSelected] : [])
    }

    @ViewBuilder private func transcripcion(_ c: ConversacionGrabada) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { verTexto.toggle() } } label: {
            HStack {
                Text("Transcripción").font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
                Spacer()
                Image(systemName: verTexto ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.s1Tinta2)
            }
            .padding(.top, 32).padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(verTexto ? "Abierta" : "Cerrada")
        if verTexto {
            if completa == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Esqueleto(alto: 14)
                    Esqueleto(alto: 14)
                    Esqueleto(alto: 14, ancho: 180)
                }
            } else if c.transcripcion.isEmpty {
                Text("—").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            } else {
                Text(c.transcripcion).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func boton(_ c: ConversacionGrabada) -> some View {
        if c.lista {
            ShareLink(item: c.textoParaCompartir) {
                Text("Compartir").font(S1Tipo.cuerpoFuerte).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EstiloRelieve(naranja: true))
        } else if c.fallo {
            BotonS1(reintentando ? "Reintentando…" : "Reintentar") { reintentar(c) }.disabled(reintentando)
        } else {
            BotonS1(borrando ? "Borrando…" : "Borrar", naranja: false) { confirmar = true }.disabled(borrando)
        }
    }

    private func cargar() async {
        guard Cuenta.compartida.activa else { return }
        if let c = try? await api.verConversacion(conversacion.id) { completa = c }
    }

    private func reintentar(_ c: ConversacionGrabada) {
        reintentando = true
        Task {
            defer { reintentando = false }
            do {
                try await api.reintentarConversacion(c.id)
                error = ""
                alCambiar()
            } catch let e as ErrorApi {
                error = e.mensaje
            } catch {
                self.error = "No pude"
            }
            await cargar()
        }
    }

    private func borrar() {
        borrando = true
        Task {
            do {
                try await api.borrarConversacion(conversacion.id)
                alCambiar()
                cerrar()
            } catch let e as ErrorApi {
                error = e.mensaje
                borrando = false
            } catch {
                self.error = "No pude"
                borrando = false
            }
        }
    }

    private func escuchar() {
        guard oyente == nil, Cuenta.compartida.activa else { return }
        let id = conversacion.id
        oyente = EnVivo.compartido.escuchar { e in
            guard e.tipo == "grabacion", (e.datos["id"] as? NSNumber)?.intValue == id else { return }
            Task { await cargar() }
        }
    }

    private func dejar() {
        if let o = oyente { EnVivo.compartido.dejar(o) }
        oyente = nil
    }
}
