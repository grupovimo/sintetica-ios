import PhotosUI
import SwiftUI

/// Una cara de imagen: el ojo, el ojo cerrado y la boca son dibujos (SVG, PNG,
/// JPEG o GIF) que el robot anima vivos. Cada parte se sube al toque; la
/// pantalla de arriba la dibuja el núcleo con sus sprites. Como
/// web/src/routes/robots/[id]/expresiones/DeImagen.svelte.
@MainActor
struct LabDeImagen: View {
    let modelo: ModeloRobot
    let inicial: String
    let alListo: (String) -> Void
    @State private var doc: [String: Any] = ["sprites": [String: Any](), "tamano": 0.4]
    @State private var nombre = ""
    @State private var siempre = false
    @State private var pegando: String?
    @State private var svg = ""
    @State private var subiendo: String?
    @State private var paraSubir = "ojo"
    @State private var eligiendo = false
    @State private var item: PhotosPickerItem?
    @State private var error = ""
    @State private var guardando = false
    @State private var arranco = false

    private let partes: [(String, String, String)] = [("ojo", "Ojo", "eye"), ("ojo_cerrado", "Cerrado", "eye.slash"), ("boca", "Boca", "mouth")]
    private let perillas: [(String, String, Double, Double, Double)] = [
        ("tamano", "Tamaño", 0.08, 0.8, 0.36), ("sep", "Separación", 0.15, 0.45, 0.3), ("ey", "Altura", -0.25, 0.25, 0), ("boca_y", "Boca", -0.7, 0.3, -0.36),
    ]

    private var spritesDoc: [String: Any] { doc["sprites"] as? [String: Any] ?? [:] }
    private func spriteDe(_ p: String) -> Int? { (spritesDoc[p] as? NSNumber)?.intValue }
    private var nombreVista: String { nombreValido(nombre) ? nombre : "vista-previa" }

    /// Lo que se dibuja: la cara que se está armando.
    private var configVista: String {
        var c = ConfigDoc(texto: modelo.config.paraDibujar)
        if spriteDe("ojo") != nil { c.ponerExpresion(nombreVista, doc) }
        return c.texto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PantallaDibujada(config: configVista, expresion: spriteDe("ojo") != nil ? nombreVista : "neutral", pantalla: modelo.pantalla, fps: 24, escala: 2)
                .aspectRatio(modelo.pantalla.redonda ? 1 : 320 / 172, contentMode: .fit)
                .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                .padding(14)
                .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
            Visor(relleno: 10) {
                Grabado("Nombre")
                TextField("", text: $nombre).font(Tipos.marca(20, .black)).foregroundStyle(Color.brasa)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Flujo(espacio: 8, renglon: 4) {
                Button { siempre.toggle() } label: { Label("Siempre", systemImage: siempre ? "star.fill" : "star") }.tecla(.negra, chica: true, hundida: siempre)
                if !inicial.isEmpty { Button { Task { await borrar() } } label: { Text("Borrar") }.tecla(.negra, chica: true) }
                Button { Task { await guardar() } } label: { Text(guardando ? "Guardando…" : "Guardar") }.tecla(.naranja, chica: true)
                    .disabled(guardando || spriteDe("ojo") == nil)
                Button { alListo(inicial) } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true).accessibilityLabel("Cerrar")
            }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                HStack(spacing: 8) {
                    ForEach(partes, id: \.0) { p, t, icono in parte(p, t, icono) }
                }
                if let p = pegando { pegar(p) }
                Bandeja {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 12) {
                        ForEach(perillas, id: \.0) { k, t, mn, mx, d in
                            Perilla(nombre: t, valor: valor(k, d), min: mn, max: mx, paso: 0.01, tamano: 48) { v in poner(k, v, d) }
                        }
                    }
                }
            }
        }
        .photosPicker(isPresented: $eligiendo, selection: $item, matching: .images)
        .onChange(of: item) { _, i in
            guard let i else { return }
            let p = paraSubir
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) { await subir(p, .datos(d)) }
                item = nil
            }
        }
        .onAppear(perform: arrancar)
    }

    private func arrancar() {
        guard !arranco else { return }
        arranco = true
        if let o = modelo.config.expresiones[inicial] as? [String: Any], esImagen(o) { doc = o }
        nombre = inicial.isEmpty ? nombreLibre() : inicial
        siempre = !inicial.isEmpty && modelo.config.caraSiempre == inicial
    }

    private func nombreLibre() -> String {
        var n = "mi-imagen", k = 2
        while modelo.config.expresiones[n] != nil { n = "mi-imagen-\(k)"; k += 1 }
        return n
    }

    private func parte(_ p: String, _ t: String, _ icono: String) -> some View {
        let n = spriteDe(p)
        return Bandeja(relleno: 10, espacio: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.hundido)
                if let n, let img = modelo.miniSprites[n] {
                    Image(uiImage: img).resizable().scaledToFit().padding(6)
                } else if subiendo == p {
                    ProgressView().tint(Color.brasa)
                } else {
                    Image(systemName: icono).font(.system(size: 24)).foregroundStyle(Color.gris)
                }
            }
            .frame(height: 64)
            Grabado(t, color: Color.tinta.opacity(0.7))
            HStack(spacing: 4) {
                Button { paraSubir = p; eligiendo = true } label: { Image(systemName: "arrow.up") }.tecla(chica: true).accessibilityLabel("Subir \(t)")
                Button { pegando = pegando == p ? nil : p } label: { Text("</>") }.tecla(chica: true, hundida: pegando == p).accessibilityLabel("Pegar un SVG")
                if n != nil && p != "ojo" {
                    Button { quitar(p) } label: { Image(systemName: "xmark") }.tecla(.negra, chica: true).accessibilityLabel("Sacar")
                }
            }
            .disabled(subiendo != nil)
        }
    }

    private func pegar(_ p: String) -> some View {
        Bandeja {
            TextEditor(text: $svg).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.papel)
                .scrollContentBackground(.hidden).frame(height: 110).padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button {
                let t = svg.trimmingCharacters(in: .whitespacesAndNewlines)
                pegando = nil
                svg = ""
                Task { await subir(p, .svg(t)) }
            } label: { Text("Listo") }.tecla(.naranja, chica: true)
                .disabled(!svg.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"))
        }
    }

    private func valor(_ k: String, _ d: Double) -> Double { (doc[k] as? NSNumber)?.doubleValue ?? d }

    private func poner(_ k: String, _ v: Double, _ d: Double) {
        var n = doc
        if abs(v - d) < 0.0005 && k != "tamano" { n.removeValue(forKey: k) } else { n[k] = v }
        doc = n
    }

    private func quitar(_ p: String) {
        var s = spritesDoc
        s.removeValue(forKey: p)
        doc["sprites"] = s
    }

    private func subir(_ p: String, _ f: ModeloRobot.FuenteSprite) async {
        error = ""
        subiendo = p
        defer { subiendo = nil }
        var usados = modelo.config.spritesEnUso(menos: inicial)
        for (_, x) in spritesDoc { if let v = (x as? NSNumber)?.intValue { usados.insert(v) } }
        guard let n = spriteDe(p) ?? spriteLibre(usados: usados) else { error = "No hay lugar: borrá otra cara de imagen."; return }
        do {
            try await modelo.subirSprite(n, f)
            var s = spritesDoc
            s[p] = n
            doc["sprites"] = s
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func guardar() async {
        error = ""
        guard nombreValido(nombre) else { error = "Minúsculas, sin espacios."; return }
        guard spriteDe("ojo") != nil else { error = "Falta el ojo."; return }
        let antes = spritesDeCara(inicial)
        var c = modelo.config
        if !inicial.isEmpty && inicial != nombre { c.ponerExpresion(inicial, nil) }
        c.ponerExpresion(nombre, doc)
        if siempre { c.ponerCaraSiempre(nombre) } else if c.caraSiempre == inicial || c.caraSiempre == nombre { c.ponerCaraSiempre("") }
        guardando = true
        let e = await modelo.guardarAhora(c)
        guardando = false
        if let e { error = e; return }
        await soltar(antes, c)
        alListo(nombre)
    }

    private func borrar() async {
        let antes = spritesDeCara(inicial)
        var c = modelo.config
        c.ponerExpresion(inicial, nil)
        if c.caraSiempre == inicial { c.ponerCaraSiempre("") }
        if let e = await modelo.guardarAhora(c) { error = e; return }
        await soltar(antes, c)
        alListo("")
    }

    private func spritesDeCara(_ n: String) -> [Int] {
        let s = ((modelo.config.expresiones[n] as? [String: Any])?["sprites"] as? [String: Any]) ?? [:]
        return s.values.compactMap { ($0 as? NSNumber)?.intValue }
    }

    /// Borra los sprites que quedaron sin usar.
    private func soltar(_ antes: [Int], _ c: ConfigDoc) async {
        let enUso = c.spritesEnUso()
        for n in antes where !enUso.contains(n) { await modelo.borrarSprite(n) }
    }
}
