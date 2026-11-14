import SwiftUI

/// 09 · Charla: el hilo con la S1. Sus respuestas llevan su cara de 32 con la
/// expresión de la respuesta; la pantalla de 72 va solo cuando hizo o mostró
/// algo (APP.md, regla 2). Abajo, el renglón y el botón naranja redondo.
@MainActor
struct CharlaS1: View {
    let sesion: SesionS1
    @Binding var borrador: String
    @Binding var enfocar: Bool
    @FocusState private var enfocado: Bool

    private static let sugerencias = ["¿Llueve hoy?", "Poné un timer de 10", "Contame un chiste", "¿Qué hay hoy?"]

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Charla", sesion: sesion)
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            renglon
        }
        .background(FondoConsola())
        .onAppear {
            if enfocar { enfocado = true; enfocar = false }
        }
    }

    @ViewBuilder private var contenido: some View {
        let modelo = sesion.modelo
        if case .conectando = modelo.fase {
            ScrollView { EstadoCargando(renglones: 3).padding(.horizontal, 20).padding(.top, 24) }
        } else if sesion.estado == .sinConexion && sesion.charla == nil {
            ScrollView {
                EstadoSinConexion(nombre: sesion.nombre, detalle: modelo.esNube ? "Visto \(hace(modelo.robot?.ultimaConexion))" : "") {
                    Task { await sesion.reintentar() }
                }
                .padding(.horizontal, 20).padding(.top, 24)
            }
        } else if sesion.hilo.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    EstadoVacio(texto: "¿De qué charlamos?", expresion: "contento")
                    Flujo(espacio: 8, renglon: 8) {
                        ForEach(Self.sugerencias, id: \.self) { s in
                            ChipS1(s) { Task { await sesion.enviar(s) } }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            hilo
        }
    }

    private var hilo: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(sesion.hilo) { m in
                        burbuja(m).id(m.id)
                    }
                    if sesion.pensando {
                        HStack(alignment: .top, spacing: 12) {
                            MarcoPantalla(tamano: .charla) { CaraDibujada(expresion: "pensando", config: sesion.modelo.config.paraDibujar, pantalla: sesion.modelo.pantalla) }
                            PuntitosPensando().padding(.top, 10)
                        }
                        .id("pensando")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { bajar(lector, animado: false) }
            .onChange(of: sesion.hilo.count) { _, _ in bajar(lector) }
            .onChange(of: sesion.pensando) { _, _ in bajar(lector) }
        }
    }

    private func bajar(_ lector: ScrollViewProxy, animado: Bool = true) {
        let pensando = sesion.pensando
        let ultimo = sesion.hilo.last?.id
        let ir = {
            if pensando {
                lector.scrollTo("pensando", anchor: .bottom)
            } else if let ultimo {
                lector.scrollTo(ultimo, anchor: .bottom)
            }
        }
        if animado { withAnimation(.easeOut(duration: 0.25)) { ir() } } else { ir() }
    }

    @ViewBuilder private func burbuja(_ m: MensajeS1) -> some View {
        if m.deMi {
            VStack(alignment: .trailing, spacing: 4) {
                Text(m.texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
                if m.sinEnviar { Text("Sin enviar").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 64)
        } else {
            HStack(alignment: .top, spacing: 12) {
                MarcoPantalla(tamano: .charla) {
                    CaraDibujada(expresion: nombreDibujable(m.expresion), config: sesion.modelo.config.paraDibujar, pantalla: sesion.modelo.pantalla, fps: 8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                    if m.hizo, m.id == sesion.hilo.last?.id { PantallaS1(sesion: sesion, tamano: .header) }
                    if m.fallo {
                        Button { Task { await sesion.reintentar(m) } } label: { Text("Reintentar") }.tecla(chica: true)
                    }
                }
                Spacer(minLength: 40)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var renglon: some View {
        let vacio = borrador.trimmingCharacters(in: .whitespaces).isEmpty
        let tope = sesion.charla != nil ? MAX_CHARLA : MAX_TEXTO
        let puede = sesion.charla?.puede ?? sesion.modelo.conectado
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 8) {
            TextField("", text: $borrador, prompt: Text("Escribile a \(sesion.nombre)").foregroundColor(Color.s1Tinta3))
                .font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).tint(Color.s1Naranja)
                .focused($enfocado)
                .submitLabel(.send)
                .onSubmit(enviar)
                .onChange(of: borrador) { _, v in let x = cortarBytes(v, tope); if x != v { borrador = x } }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(forma.fill(Color.s1Campo))
                .overlay(forma.strokeBorder(Color.s1Linea, lineWidth: 1))
            if vacio && sesion.puedeHablar {
                HablarRedondo(activa: sesion.conversacion.activa, alApretar: { sesion.hablar() }, alSoltar: { sesion.soltarHablar() })
                    .disabled(!sesion.modelo.conectado)
            } else {
                Button(action: enviar) {
                    ZStack {
                        if vacio {
                            Rejilla(tamano: 28)
                        } else {
                            IconoS1(.mandar, tamano: 22)
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(EstiloRelieve(naranja: true, radio: 24))
                .disabled(vacio || sesion.pensando || !puede)
                .accessibilityLabel("Mandar")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color.s1Fondo)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
    }

    private func enviar() {
        let t = borrador
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty, !sesion.pensando else { return }
        borrador = ""
        Task { await sesion.enviar(t) }
    }
}

/// Los tres puntitos de "pensando".
struct PuntitosPensando: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let f = (sin(t * 5 - Double(i) * 0.8) + 1) / 2
                    Circle().fill(Color.s1Tinta2).frame(width: 8, height: 8)
                        .opacity(0.4 + 0.6 * f)
                        .offset(y: -6 * f)
                }
            }
        }
        .frame(height: 20)
        .accessibilityLabel("Pensando")
    }
}

/// El botón redondo de la charla vacío: mantené para hablar (apretar arranca,
/// soltar termina).
struct HablarRedondo: View {
    let activa: Bool
    let alApretar: () -> Void
    let alSoltar: () -> Void
    @State private var apretada = false
    @Environment(\.isEnabled) private var habilitada

    var body: some View {
        ZStack {
            Circle().fill(Color.s1NaranjaCanto).offset(y: apretada ? 1 : 4)
            Circle().fill(LinearGradient(colors: [Color.s1NaranjaBrillo, Color.s1Naranja], startPoint: .top, endPoint: .bottom))
                .offset(y: apretada ? 3 : 0)
            Group {
                if activa { IconoS1(.sistema("stop.fill"), tamano: 18).foregroundStyle(Color.s1TintaFija) } else { Rejilla(tamano: 28) }
            }
            .offset(y: apretada ? 3 : 0)
        }
        .frame(width: 48, height: 48)
        .padding(.bottom, 4)
        .opacity(habilitada ? 1 : 0.4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard habilitada, !apretada else { return }
                    apretada = true
                    alApretar()
                }
                .onEnded { _ in
                    guard apretada else { return }
                    apretada = false
                    alSoltar()
                }
        )
        .animation(.easeOut(duration: 0.08), value: apretada)
        .sensoryFeedback(.impact(weight: .medium), trigger: apretada)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mantené para hablar")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { alApretar() }
    }
}
