import SwiftUI

/// Dibujos: las caras hechas con formas (las 16 del manual y las tuyas), con
/// miniaturas sacadas del núcleo. Se ven en vivo, se prueban en el robot, se
/// copian y se borran (o vuelven a la del manual). Como
/// web/src/routes/robots/[id]/caras/+page.svelte, sin el editor de formas.
@MainActor
struct LabDibujos: View {
    let modelo: ModeloRobot
    @State private var fotos: [String: UIImage] = [:]
    @State private var elegido = "contento"
    @State private var error = ""
    @State private var aviso = ""
    @State private var editando: (nombre: String, doc: [String: Any])?

    private var propios: [String: [String: Any]] {
        var d: [String: [String: Any]] = [:]
        for (k, v) in modelo.config.expresiones { if let o = v as? [String: Any], o["formas"] != nil { d[k] = o } }
        return d
    }

    private var nombres: [String] {
        let base = VidaBase.dibujos.map(\.nombre)
        return base + propios.keys.filter { !base.contains($0) }.sorted()
    }

    private func docDe(_ n: String) -> [String: Any]? { propios[n] ?? VidaBase.dibujos.first { $0.nombre == n }?.doc }
    private var esDelManual: Bool { VidaBase.dibujos.contains { $0.nombre == elegido } }

    var body: some View {
        if let e = editando {
            LabDibujoEditor(modelo: modelo, inicial: e.nombre, doc: e.doc) { n in
                editando = nil
                if !n.isEmpty { elegido = n }
            }
            .id(e.nombre)
        } else {
            galeria
        }
    }

    private var galeria: some View {
        VStack(alignment: .leading, spacing: 16) {
            PantallaNucleo()
                .aspectRatio(modelo.pantalla.aspecto, contentMode: .fit)
                .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                .padding(14)
                .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
            HStack {
                Text(elegido.uppercased()).font(Tipos.marca(22, .black)).foregroundStyle(Color.papel).lineLimit(1).minimumScaleFactor(0.6)
                if propios[elegido] != nil { Led(estado: .on, tamano: 7) }
                Spacer()
            }
            Flujo(espacio: 8, renglon: 4) {
                Button { editando = (elegido, docDe(elegido) ?? [:]) } label: { Label("Editar", systemImage: "pencil") }.tecla(.naranja, chica: true)
                Button { editando = ("", VidaBase.dibujos.first { $0.nombre == "neutral" }?.doc ?? [:]) } label: { Label("Nueva", systemImage: "plus") }
                    .tecla(chica: true)
                Button { enRobot() } label: { Label("En el robot", systemImage: "play.fill") }.tecla(.negra, chica: true).disabled(!modelo.conectado)
                Button { copiar() } label: { Label("Copiar", systemImage: "plus.square.on.square") }.tecla(chica: true)
                if propios[elegido] != nil {
                    Button { borrar() } label: { Text(esDelManual ? "Original" : "Borrar") }.tecla(.negra, chica: true)
                }
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso) }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(nombres, id: \.self) { n in miniatura(n) }
                }
            }
        }
        .task(id: modelo.config.texto) { fotografiar() }
        .onDisappear { modelo.pausarEspejo(0) }
    }

    private func miniatura(_ n: String) -> some View {
        let sel = n == elegido
        let alto: CGFloat = modelo.pantalla.redonda ? 80 : 46
        return Button { ver(n) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Color.black
                    if let f = fotos[n] { Image(uiImage: f).resizable().scaledToFill() }
                }
                .frame(height: alto)
                .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                HStack(spacing: 4) {
                    Text(n).font(Tipos.marca(9.5, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    if propios[n] != nil { Led(estado: .on, tamano: 6) }
                }
                .foregroundStyle(sel ? Color.papel : Color.tinta)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(sel ? Color.tinta : Color.tinta.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n)
        .accessibilityAddTraits(sel ? [.isSelected] : [])
    }

    /// Las miniaturas: los dibujos como propios en el núcleo del celu, uno por uno.
    private func fotografiar() {
        var c = ConfigDoc(["version": 2])
        if let cara = modelo.config.raiz["cara"] { c.raiz["cara"] = cara }
        var e: [String: Any] = [:]
        for n in nombres.prefix(24) { if let d = docDe(n) { e[n] = d } }
        c.raiz["expresiones"] = e
        let l = Nucleo.fotografiar(config: c.texto, nombres: Array(nombres.prefix(24)))
        var f: [String: UIImage] = [:]
        for (k, v) in l { f[k] = UIImage(cgImage: v) }
        fotos = f
        modelo.aplicarEnVistaPrevia(modelo.config.texto)
        ver(elegido)
    }

    /// Lo muestra en la vista previa (si es del manual y no es tuyo, como propio un rato).
    private func ver(_ n: String) {
        elegido = n
        modelo.pausarEspejo(30)
        var c = modelo.config
        if propios[n] == nil, let d = docDe(n) { c.ponerExpresion(n, d) }
        modelo.aplicarEnVistaPrevia(c.texto)
        Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.expresion(n)))
    }

    private func enRobot() {
        let n = elegido
        Task {
            if let e = await modelo.comando(["expresion": n]) { error = e; return }
            try? await Task.sleep(for: .seconds(4))
            await modelo.comando(["expresion": ""])
        }
    }

    private func copiar() {
        guard let d = docDe(elegido) else { return }
        var n = "mi-\(elegido)", k = 2
        while propios[n] != nil || VidaBase.expresiones[n] != nil { n = "mi-\(elegido)-\(k)"; k += 1 }
        let nombre = String(n.prefix(24))
        guardar { $0.ponerExpresion(nombre, d) } listo: { "«\(nombre)» está en el robot." }
        elegido = nombre
    }

    private func borrar() {
        let n = elegido
        let manual = esDelManual
        guardar { $0.ponerExpresion(n, nil) } listo: { manual ? "Volvió a la del manual." : "Se borró." }
        if !manual { elegido = "contento" }
    }

    private func guardar(_ f: (inout ConfigDoc) -> Void, listo: @escaping () -> String) {
        var c = modelo.config
        f(&c)
        error = ""
        Task {
            if let e = await modelo.guardarAhora(c) { error = e; return }
            aviso = listo()
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

/// Animaciones: las tuyas y las de ejemplo. Se ven en vivo, se reproducen en
/// el robot, se suman las de ejemplo y se borran. Como
/// web/src/routes/robots/[id]/animaciones/+page.svelte, sin el editor de pistas.
@MainActor
struct LabAnimaciones: View {
    let modelo: ModeloRobot
    @State private var error = ""
    @State private var aviso = ""

    private var propias: [String: Any] { modelo.config.raiz["animaciones"] as? [String: Any] ?? [:] }
    private var configUsuario: String { modelo.config.paraDibujar }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PantallaNucleo()
                .aspectRatio(modelo.pantalla.aspecto, contentMode: .fit)
                .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                .padding(14)
                .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
            if !aviso.isEmpty { AvisoConsola(texto: aviso) }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                Grabado("Tuyas", color: Color.tinta.opacity(0.66))
                if propias.isEmpty {
                    Text("Ninguna todavía.").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
                }
                ForEach(propias.keys.sorted(), id: \.self) { n in
                    fila(n, doc: propias[n] as? [String: Any] ?? [:], propia: true)
                }
                Grabado("Ejemplos", color: Color.tinta.opacity(0.66))
                ForEach(VidaBase.animaciones, id: \.nombre) { a in fila(a.nombre, doc: a.doc, propia: false) }
            }
        }
        .onDisappear { modelo.pausarEspejo(0) }
    }

    private func fila(_ n: String, doc: [String: Any], propia: Bool) -> some View {
        let sobre = doc["sobre"] as? String ?? "neutral"
        let ms = (doc["duracion"] as? NSNumber)?.intValue ?? 0
        return Bandeja(relleno: 12, espacio: 10) {
            HStack(spacing: 12) {
                MiniCara(nombre: sobre, config: configUsuario, pantalla: modelo.pantalla, ancho: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.uppercased()).font(Tipos.marca(15, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                    Grabado(String(format: "%.1f s", Double(ms) / 1000) + ((doc["repetir"] as? Bool ?? false) ? " · en bucle" : ""), color: Color.tinta.opacity(0.6))
                }
                Spacer(minLength: 0)
                Button { verAca(n, doc: doc) } label: { Image(systemName: "eye.fill") }.tecla(.naranja, cuadrada: true).accessibilityLabel("Verla acá")
            }
            Flujo(espacio: 8, renglon: 4) {
                if propia {
                    Button { enRobot(n) } label: { Label("En el robot", systemImage: "play.fill") }.tecla(.negra, chica: true).disabled(!modelo.conectado)
                    Button { cambiar(n, nil, "Se borró.") } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Borrar")
                } else {
                    Button { sumar(n, doc) } label: { Label("Sumar", systemImage: "plus") }.tecla(chica: true)
                }
            }
        }
    }

    private func verAca(_ n: String, doc: [String: Any]) {
        var c = modelo.config
        var a = propias
        a[n] = doc
        c.raiz["animaciones"] = a
        if let e = Nucleo.validar(c.texto) { error = e; return }
        error = ""
        modelo.pausarEspejo(8)
        modelo.aplicarEnVistaPrevia(c.texto)
        Nucleo.bleEscribir(Car.comando.rawValue, Data(Comando.reproducir(n)))
    }

    private func enRobot(_ n: String) {
        Task { error = await modelo.comando(["reproducir": n]) ?? "" }
    }

    private func sumar(_ n: String, _ doc: [String: Any]) {
        var libre = n, k = 2
        while propias[libre] != nil { libre = "\(n)-\(k)"; k += 1 }
        cambiar(libre, doc, "«\(libre)» está en el robot.")
    }

    private func cambiar(_ n: String, _ doc: [String: Any]?, _ listo: String) {
        var c = modelo.config
        var a = propias
        if let doc { a[n] = doc } else { a.removeValue(forKey: n) }
        if a.isEmpty { c.raiz.removeValue(forKey: "animaciones") } else { c.raiz["animaciones"] = a }
        error = ""
        Task {
            if let e = await modelo.guardarAhora(c) { error = e; return }
            aviso = listo
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}
