import SwiftUI

// 16 · Su cara, 32 · Su pantalla y 20 · La S1.

/// Las caras dibujadas que se eligen de un toque (las de fábrica).
let CARAS_S1: [(clave: String, nombre: String)] = [
    ("neutral", "Neutral"), ("contento", "Contenta"), ("guino", "Guiño"), ("sorpresa", "Sorpresa"),
    ("enamorado", "Enamorada"), ("pensando", "Pensando"), ("dormido", "Dormida"), ("emocionado", "Emocionada"),
]

/// Los colores de los temas (Naranja, Lima, Celeste, Rosa).
let TEMAS_S1: [(hex: String, nombre: String)] = [("#FF6A33", "Naranja"), ("#4ADE80", "Lima"), ("#3DE0FF", "Celeste"), ("#FF5FA2", "Rosa")]

/// Un mosaico de una cara (o de un tema): su pantalla chica y el nombre;
/// elegido = anillo en tinta.
struct MosaicoCara<Vista: View>: View {
    let nombre: String
    let elegido: Bool
    let accion: () -> Void
    @ViewBuilder let pantalla: Vista

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 8) {
                MarcoPantalla(tamano: .lista) { pantalla }
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(elegido ? Color.s1Inv : Color.clear, lineWidth: 2))
                Text(nombre).font(elegido ? S1Tipo.captionFuerte : S1Tipo.caption).foregroundStyle(Color.s1Tinta)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nombre)
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: elegido)
    }
}

/// 16 · Su cara: la de 160 con la elegida, las caras dibujadas, tu dibujo o
/// una foto, y "Dejarla así". Abajo, sus ojos.
@MainActor
struct SuCaraS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var elegida = "neutral"
    @State private var aviso = ""
    @State private var poniendo = false

    var body: some View {
        let modelo = sesion.modelo
        let config = modelo.config.paraDibujar
        VStack(alignment: .leading, spacing: 0) {
            PantallaGrande { CaraDibujada(expresion: elegida, config: config, pantalla: modelo.pantalla) }
            Seccion("Caras")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ForEach(CARAS_S1, id: \.clave) { c in
                    MosaicoCara(nombre: c.nombre, elegido: elegida == c.clave, accion: { elegida = c.clave }) {
                        CaraDibujada(expresion: c.clave, config: config, pantalla: modelo.pantalla, fps: 6)
                    }
                }
                Button { ir(.laboratorio(.dibujos)) } label: { tile("Tu dibujo", "pencil.and.outline") }.buttonStyle(.plain)
                Button { ir(.modulo(.imagenes)) } label: { tile("Una foto", "photo") }.buttonStyle(.plain)
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso).padding(.top, 16) }
            VStack(spacing: 8) {
                BotonS1(poniendo ? "Poniendo…" : "Dejarla así") { poner(elegida) }
                    .disabled(!modelo.conectado || poniendo)
                if modelo.caraFija {
                    BotonS1("Que vuelva a ser ella", naranja: false) { poner("") }.disabled(!modelo.conectado)
                }
            }
            .padding(.top, 24)
            Seccion("Sus ojos")
            ModCara(modelo: modelo)
        }
        .onAppear {
            let e = modelo.estado?.expresion ?? ""
            if CARAS_S1.contains(where: { $0.clave == e }) { elegida = e }
        }
    }

    private func tile(_ t: String, _ simbolo: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Superficie)
                Image(systemName: simbolo).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.s1Tinta)
            }
            .frame(width: 48, height: 48)
            .padding(3)
            Text(t).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func poner(_ n: String) {
        poniendo = true
        Task {
            let e = await sesion.modelo.comando(["expresion": n])
            poniendo = false
            aviso = e ?? (n.isEmpty ? "Vuelve a ser ella." : "Lista.")
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

/// 32 · Su pantalla: los temas, las frases por momento, los reflejos, el
/// diario y lo que muestra (compañía, reloj, galería…).
@MainActor
struct SuPantallaS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void

    private static let frases: [(situacion: String, momento: String, ejemplo: String)] = [
        ("despertar", "Al despertar", "«Buen día»"), ("volviste", "Cuando volvés", "«¡Volviste!»"),
        ("buenas-noches", "A la noche", "«Hasta mañana»"), ("caricia", "Si la acariciás", "«Más, más»"),
    ]

    var body: some View {
        let modelo = sesion.modelo
        let c = modelo.config
        VStack(alignment: .leading, spacing: 0) {
            Seccion("Temas", arriba: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ForEach(TEMAS_S1, id: \.hex) { t in
                    MosaicoCara(nombre: t.nombre, elegido: c.colorOjos == t.hex, accion: { modelo.cambiar { $0.ponerColor(t.hex) } }) {
                        CaraDibujada(expresion: "contento", config: conColor(c, t.hex), pantalla: modelo.pantalla, fps: 6)
                    }
                }
            }
            Seccion("Frases por momento")
            VStack(spacing: 0) {
                ForEach(Self.frases, id: \.situacion) { f in
                    let propia = c.frasesPropias[f.situacion]?.first
                    Button { ir(.modulo(.habla)) } label: {
                        FilaS1(titulo: f.momento, detalle: propia.map { "«\($0)»" } ?? f.ejemplo, flecha: true) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
            }
            Seccion("Reflejos")
            VStack(spacing: 0) {
                Button { ir(.modulo(.reflejos)) } label: {
                    FilaS1(titulo: "Cómo reacciona", detalle: "Caricias, toques, sacudidas", flecha: true) { IconoEnCirculo(icono: .sistema("cable.connector")) }
                }
                .buttonStyle(.plain)
                FilaToggle(titulo: "Habla sola", detalle: "Cada tanto, en un globo", prendido: c.frecuenciaHabla > 0.05) {
                    let v = c.frecuenciaHabla > 0.05 ? 0.0 : 0.5
                    modelo.cambiar { $0.ponerFrecuenciaHabla(v) }
                }
            }
            Seccion("El diario")
            Button { ir(.modulo(.diario)) } label: {
                FilaS1(titulo: "Lo que pasó", detalle: "Lo que guarda de cada día", flecha: true) { IconoEnCirculo(icono: .sistema("sparkles")) }
            }
            .buttonStyle(.plain)
            Seccion("Qué muestra")
            ModModos(modelo: modelo)
        }
    }

    private func conColor(_ c: ConfigDoc, _ hex: String) -> String {
        var x = c
        x.ponerColor(hex)
        return x.paraDibujar
    }
}

/// 20 · La S1: brillo, volumen, cómo se porta, WiFi y batería, cuando
/// descansa, los botones, actualizar, desvincular y "Hacerla sonar".
@MainActor
struct LaS1Vista: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    let volver: () -> Void
    @State private var nombre = ""
    @State private var error = ""
    @State private var aviso = ""
    @State private var seguro = false
    @State private var quitando = false
    @State private var nueva: VersionFirmware?
    @State private var actualizando = false

    var body: some View {
        let modelo = sesion.modelo
        let c = modelo.config
        let e = modelo.estado
        let brillo = Int((c.brilloMax * 10).rounded())
        let volumen = Int((((c.voz["volumen"] as? NSNumber)?.doubleValue ?? 0.7) * 10).rounded())
        VStack(alignment: .leading, spacing: 0) {
            if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.bottom, 16) }
            CampoS1(ayuda: "Su nombre", texto: $nombre) {
                let n = nombre
                if n != modelo.nombre { Task { error = await modelo.ponerApodo(n) ?? "" } }
            }
            .onChange(of: nombre) { _, v in let x = cortarBytes(v, 24); if x != v { nombre = x } }
            VStack(spacing: 0) {
                FilaPasos(titulo: "Brillo", valor: "\(brillo)", puedeMenos: brillo > 2, puedeMas: brillo < 10,
                          menos: { modelo.cambiar { $0.ponerBrillo(Double(max(2, brillo - 1)) / 10) } },
                          mas: { modelo.cambiar { $0.ponerBrillo(Double(min(10, brillo + 1)) / 10) } })
                if modelo.producto.tiene(.parlante) {
                    FilaPasos(titulo: "Volumen", valor: "\(volumen)", puedeMenos: volumen > 0, puedeMas: volumen < 10,
                              menos: { modelo.cambiar { $0.ponerVoz("volumen", Double(max(0, volumen - 1)) / 10) } },
                              mas: { modelo.cambiar { $0.ponerVoz("volumen", Double(min(10, volumen + 1)) / 10) } })
                }
            }
            .padding(.top, 16)
            Seccion("Cómo se porta")
            VStack(spacing: 0) {
                FilaToggle(titulo: "Te pregunta cómo estás", prendido: c.cuidado.animo) { modelo.cambiar { $0.cambiarCuidado { $0.animo.toggle() } } }
                FilaToggle(titulo: "Te extraña si no le hablás", prendido: c.cuidado.extranar) { modelo.cambiar { $0.cambiarCuidado { $0.extranar.toggle() } } }
                FilaToggle(titulo: "Te despide cuando te vas", prendido: c.presenciaPregunta) {
                    modelo.cambiar { $0.ponerPresencia(preguntar: !c.presenciaPregunta, texto: c.presenciaTexto) }
                }
                FilaToggle(titulo: "Habla sola", prendido: c.frecuenciaHabla > 0.05) {
                    let v = c.frecuenciaHabla > 0.05 ? 0.0 : 0.5
                    modelo.cambiar { $0.ponerFrecuenciaHabla(v) }
                }
            }
            VStack(spacing: 0) {
                Button { if modelo.vinculado || modelo.esBle { ir(.cerca) } } label: {
                    FilaS1(titulo: "WiFi", valor: e?.wifi == true ? "Conectada" : "Sin wifi", flecha: modelo.vinculado || modelo.esBle) { EmptyView() }
                }
                .buttonStyle(.plain)
                FilaS1(titulo: "Batería", valor: e?.bateria.map { "\($0)%" } ?? "—") { EmptyView() }
                FilaS1(titulo: "Versión", valor: (e?.version).flatMap { $0.isEmpty ? nil : $0 } ?? "—") { EmptyView() }
            }
            .padding(.top, 24)
            Seccion("Cuando descansa")
            Flujo(espacio: 8, renglon: 8) {
                ChipS1("Su cara", elegido: c.modo == "mascota") { modelo.cambiar { $0.ponerModo("mascota") } }
                ChipS1("Reloj", elegido: c.modo == "reloj") { modelo.cambiar { $0.ponerModo("reloj") } }
                ChipS1("Galería", elegido: c.modo == "galeria") { modelo.cambiar { $0.ponerModo("galeria") } }
                ChipS1("Clima", elegido: c.modo == "clima") { modelo.cambiar { $0.ponerModo("clima") } }
            }
            Seccion("Botones")
            VStack(spacing: 0) {
                FilaS1(titulo: "Botón de arriba", valor: "Hablar") { EmptyView() }
                FilaS1(titulo: "Botón de abajo", valor: "La hora y el clima") { EmptyView() }
                FilaS1(titulo: "Mantenerlo apretado", valor: "El volumen") { EmptyView() }
            }
            Seccion("Sistema")
            VStack(spacing: 0) {
                if modelo.esNube {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Actualizar").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                            Text(nueva.map { "Hay una nueva: \($0.version)" } ?? "Está al día").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                        }
                        Spacer()
                        if nueva != nil {
                            Button { actualizar() } label: { Text(actualizando ? "…" : "Actualizar") }.tecla(chica: true)
                                .disabled(actualizando || !modelo.conectado)
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Desvincular").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                        Text(modelo.esNube ? "Se borra de tu cuenta" : "Se olvida de este celu").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                    }
                    Spacer()
                    Button { quitar() } label: { Text(quitando ? "…" : seguro ? "¿Seguro?" : "Desvincular") }.tecla(chica: true).disabled(quitando)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso).padding(.top, 16) }
            BotonS1("Hacerla sonar", naranja: false) { sonar() }
                .disabled(!modelo.conectado)
                .padding(.top, 24)
        }
        .onAppear { nombre = modelo.nombre == "Tu robot" ? "" : modelo.nombre }
        .task { await buscarVersion() }
    }

    private func buscarVersion() async {
        let m = sesion.modelo
        guard m.esNube, !m.perfil.isEmpty else { return }
        let actual = m.estado?.version ?? ""
        if let l = try? await Cuenta.compartida.api.versionesFirmware(perfil: m.perfil), let u = l.first, u.version != actual, !actual.isEmpty {
            nueva = u
        }
    }

    private func actualizar() {
        guard let n = nueva else { return }
        actualizando = true
        Task {
            do {
                _ = try await Cuenta.compartida.api.actualizar(sesion.id, firmware: n.id)
                aviso = "Se está actualizando."
                nueva = nil
            } catch {
                self.error = error.localizedDescription
            }
            actualizando = false
        }
    }

    private func sonar() {
        Task {
            _ = await sesion.modelo.comando(["evento": "nombre"])
            aviso = await sesion.modelo.decir("¡Acá estoy!") ?? "Está sonando."
            try? await Task.sleep(for: .seconds(3))
            aviso = ""
        }
    }

    private func quitar() {
        if !seguro {
            seguro = true
            Task { try? await Task.sleep(for: .seconds(5)); seguro = false }
            return
        }
        quitando = true
        Task {
            if let e = await sesion.modelo.quitar() {
                error = e
                quitando = false
            } else {
                volver()
            }
        }
    }
}
