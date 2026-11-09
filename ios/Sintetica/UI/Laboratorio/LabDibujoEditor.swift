import SwiftUI

/// El editor de dibujos (las caras con formas): el núcleo del celu dibuja la
/// cara y encima se arrastran las formas; la elegida se ajusta con sus campos.
/// Como web/src/lib/componentes/EditorCara.svelte.
@MainActor
struct LabDibujoEditor: View {
    let modelo: ModeloRobot
    let inicial: String
    let doc: [String: Any]
    let alListo: (String) -> Void
    @State private var nombre = ""
    @State private var formas: [Forma] = []
    @State private var parpadea = true
    @State private var sel = -1
    @State private var tipoNuevo = "pildora"
    @State private var arrastre: (i: Int, x: Double, y: Double, original: Forma)?
    @State private var error = ""
    @State private var guardando = false
    @State private var reloj: Task<Void, Never>?
    @State private var arranco = false

    private var nombreVista: String { nombreValido(nombre) ? nombre : "edicion" }
    private var documento: [String: Any] {
        var d: [String: Any] = ["formas": formas]
        if !parpadea { d["parpadea"] = false }
        return d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            lienzo
            Visor(relleno: 10) {
                Grabado("Nombre")
                TextField("", text: $nombre).font(Tipos.marca(20, .black)).foregroundStyle(Color.brasa)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(!inicial.isEmpty && VidaBase.dibujos.contains { $0.nombre == inicial })
            }
            Flujo(espacio: 8, renglon: 4) {
                Llave(texto: "Parpadea", prendida: parpadea) { parpadea.toggle(); aplicar() }
                Button { Task { await guardar() } } label: { Text(guardando ? "Guardando…" : "Guardar") }.tecla(.naranja, chica: true)
                    .disabled(guardando || !nombreValido(nombre) || formas.isEmpty)
                Button { alListo(inicial) } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true).accessibilityLabel("Cerrar")
            }
            if !error.isEmpty { AvisoConsola(texto: "No la aceptaría: \(error)", error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(TIPOS_FORMA, id: \.tipo) { t in Button(t.nombre) { tipoNuevo = t.tipo } }
                    } label: {
                        Text((TIPOS_FORMA.first { $0.tipo == tipoNuevo }?.nombre ?? tipoNuevo).uppercased())
                            .font(Tipos.marca(12, .black)).foregroundStyle(Color.papel)
                            .padding(.horizontal, 12).frame(height: 40).background(RoundedRectangle(cornerRadius: 11).fill(Color.hundido))
                    }
                    Button { agregar() } label: { Label("Forma", systemImage: "plus") }.tecla(.negra, chica: true)
                }
                lista
                if sel >= 0, sel < formas.count { Bandeja { campos(sel) } }
            }
        }
        .onAppear(perform: arrancar)
        .onDisappear { modelo.pausarEspejo(0) }
    }

    // MARK: El lienzo: la cara viva y encima las cajas de las formas

    private var lienzo: some View {
        PantallaNucleo()
            .aspectRatio(modelo.pantalla.aspecto, contentMode: .fit)
            .overlay {
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    Canvas { ctx, _ in
                        for (i, f) in formas.enumerated() {
                            let r = LabDibujoEditor.rectDe(cajaDe(f), w, h)
                            let color: Color = i == sel ? .brasa : Color.white.opacity(0.25)
                            ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 4), with: .color(color),
                                       style: StrokeStyle(lineWidth: i == sel ? 2 : 1, dash: i == sel ? [] : [4, 3]))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in arrastrar(v, w: w, h: h) }
                        .onEnded { _ in arrastre = nil })
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(14)
            .chapa(radio: 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("La cara, en vivo: arrastrá una forma para moverla")
    }

    /// La caja de una forma en la vista.
    nonisolated static func rectDe(_ c: (Double, Double, Double, Double), _ w: CGFloat, _ h: CGFloat) -> CGRect {
        let alto: Double = 2 * MEDIO_ALTO
        let x: CGFloat = CGFloat((c.0 + 1) / 2) * w
        let y: CGFloat = CGFloat((c.1 + MEDIO_ALTO) / alto) * h
        let ancho: CGFloat = Swift.max(6, CGFloat((c.2 - c.0) / 2) * w)
        let altoR: CGFloat = Swift.max(6, CGFloat((c.3 - c.1) / alto) * h)
        return CGRect(x: x, y: y, width: ancho, height: altoR)
    }

    private func arrastrar(_ v: DragGesture.Value, w: CGFloat, h: CGFloat) {
        let (x, y) = aNormal(Double(v.location.x / w), Double(v.location.y / h))
        if arrastre == nil {
            let (x0, y0) = aNormal(Double(v.startLocation.x / w), Double(v.startLocation.y / h))
            guard let i = formaEn(formas, x: x0, y: y0) else { sel = -1; return }
            sel = i
            arrastre = (i, x0, y0, formas[i])
        }
        guard let a = arrastre, a.i < formas.count else { return }
        formas[a.i] = moverForma(a.original, x - a.x, y - a.y)
        aplicar()
    }

    // MARK: La lista de formas

    private var lista: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(formas.enumerated()), id: \.offset) { i, f in
                    Button { sel = i } label: {
                        Text("\(i + 1) · \(TIPOS_FORMA.first { $0.tipo == (f["forma"] as? String) }?.nombre ?? "?")")
                            .font(Tipos.marca(11, .black))
                    }
                    .tecla(chica: true, hundida: i == sel)
                }
            }
        }
    }

    @ViewBuilder private func campos(_ i: Int) -> some View {
        let f = formas[i]
        HStack(spacing: 6) {
            Button { correr(i, -1) } label: { Image(systemName: "arrow.left") }.tecla(.negra, cuadrada: true).disabled(i == 0)
            Button { correr(i, 1) } label: { Image(systemName: "arrow.right") }.tecla(.negra, cuadrada: true).disabled(i >= formas.count - 1)
            Button { duplicar(i, espejo: false) } label: { Image(systemName: "plus.square.on.square") }.tecla(.negra, cuadrada: true)
                .accessibilityLabel("Duplicar")
            Button { duplicar(i, espejo: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                .tecla(.negra, cuadrada: true).accessibilityLabel("Del otro lado")
            Spacer(minLength: 0)
            Button { quitar(i) } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Quitar")
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(camposVisibles(f), id: \.clave) { c in
                CampoNumero(nombre: c.nombre, valor: (f[c.clave] as? NSNumber)?.doubleValue ?? 0, min: c.min, max: c.max, paso: c.paso) { v in
                    poner(i, c.clave, v)
                }
            }
        }
        if f["forma"] as? String == "pildora" {
            HStack(spacing: 8) {
                Llave(texto: "Radio propio", prendida: f["r"] != nil) { poner(i, "r", f["r"] == nil ? 0.05 : nil) }
                Llave(texto: "Relleno", prendida: (f["relleno"] as? Bool) != false) {
                    var g = formas[i]
                    if (g["relleno"] as? Bool) == false { g.removeValue(forKey: "relleno"); g.removeValue(forKey: "trazo") } else { g["relleno"] = false; g["trazo"] = g["trazo"] ?? 0.02 }
                    formas[i] = g
                    aplicar()
                }
            }
        }
        Grabado("Color", color: Color.tinta.opacity(0.66))
        HStack(spacing: 6) {
            ForEach(COLORES_FORMA, id: \.self) { c in
                let elegido = (f["color"] as? String ?? "naranja") == c
                Button { poner(i, "color", c == "naranja" ? nil : c) } label: {
                    Circle().fill(Color(hex: HEX_COLOR_FORMA[c] ?? 0xFF6A33)).frame(width: 26, height: 26)
                        .overlay(Circle().stroke(elegido ? Color.tinta : Color.clear, lineWidth: 3).padding(-4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c)
            }
        }
        Llave(texto: "Fija (no parpadea)", prendida: f["fijo"] as? Bool == true) { poner(i, "fijo", f["fijo"] as? Bool == true ? nil : true) }
    }

    // MARK: Acciones

    private func arrancar() {
        guard !arranco else { return }
        arranco = true
        nombre = inicial.isEmpty ? nombreLibre() : inicial
        formas = doc["formas"] as? [Forma] ?? (doc["formas"] as? [[String: Any]] ?? [])
        if formas.isEmpty { formas = (VidaBase.dibujos.first { $0.nombre == "neutral" }?.doc["formas"] as? [[String: Any]]) ?? [formaNueva("pildora")] }
        parpadea = doc["parpadea"] as? Bool ?? true
        aplicar()
    }

    private func nombreLibre() -> String {
        var n = "mi-cara", k = 2
        while modelo.config.expresiones[n] != nil || VidaBase.expresiones[n] != nil { n = "mi-cara-\(k)"; k += 1 }
        return n
    }

    private func poner(_ i: Int, _ k: String, _ v: Any?) {
        guard i < formas.count else { return }
        if let v { formas[i][k] = v } else { formas[i].removeValue(forKey: k) }
        aplicar()
    }

    private func agregar() {
        formas.append(formaNueva(tipoNuevo))
        sel = formas.count - 1
        aplicar()
    }

    private func quitar(_ i: Int) {
        formas.remove(at: i)
        sel = min(sel, formas.count - 1)
        aplicar()
    }

    private func duplicar(_ i: Int, espejo: Bool) {
        formas.insert(espejo ? espejarForma(formas[i]) : formas[i], at: i + 1)
        sel = i + 1
        aplicar()
    }

    private func correr(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0, j < formas.count else { return }
        formas.swapAt(i, j)
        sel = j
        aplicar()
    }

    /// La pasa al núcleo del celu (validada, sin guardar) y la deja a la vista.
    private func aplicar() {
        reloj?.cancel()
        let d = documento, n = nombreVista
        reloj = Task {
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return }
            var c = modelo.config
            c.ponerExpresion(n, d)
            if let e = Nucleo.validar(c.texto) { error = e; return }
            error = ""
            modelo.pausarEspejo(600)
            modelo.aplicarEnVistaPrevia(c.texto)
            Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion(n)))
        }
    }

    private func guardar() async {
        error = ""
        guard nombreValido(nombre) else { error = "Minúsculas, sin espacios."; return }
        var c = modelo.config
        if !inicial.isEmpty, inicial != nombre { c.ponerExpresion(inicial, nil) }
        c.ponerExpresion(nombre, documento)
        guardando = true
        let e = await modelo.guardarAhora(c)
        guardando = false
        if let e { error = e; return }
        alListo(nombre)
    }
}

/// Un número con − y + (y el valor para escribir).
struct CampoNumero: View {
    let nombre: String
    let valor: Double
    let min: Double, max: Double, paso: Double
    let alCambiar: (Double) -> Void
    @State private var texto = ""

    private func poner(_ v: Double) {
        let r = (Swift.min(max, Swift.max(min, v)) * 10000).rounded() / 10000
        alCambiar(r)
        texto = String(format: "%.3f", r)
    }

    var body: some View {
        Visor(relleno: 8) {
            Grabado(nombre)
            HStack(spacing: 4) {
                Button { poner(valor - paso * 4) } label: { Image(systemName: "minus") }.tecla(.negra, cuadrada: true)
                TextField("", text: $texto).font(Tipos.marca(14, .black).monospacedDigit()).foregroundStyle(Color.brasa)
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.center)
                    .onSubmit { if let v = Double(texto.replacingOccurrences(of: ",", with: ".")) { poner(v) } }
                Button { poner(valor + paso * 4) } label: { Image(systemName: "plus") }.tecla(.negra, cuadrada: true)
            }
        }
        .onAppear { texto = String(format: "%.3f", valor) }
        .onChange(of: valor) { _, v in texto = String(format: "%.3f", v) }
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: poner(valor + paso)
            case .decrement: poner(valor - paso)
            @unknown default: break
            }
        }
    }
}
