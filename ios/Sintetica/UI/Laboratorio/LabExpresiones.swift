import SwiftUI

/// Expresiones: una galería con las caras de verdad (las dibuja el núcleo), la
/// elegida grande y viva, y perillas agrupadas por parte de la cara. Se guarda
/// solo lo que cambia respecto de la original. Como
/// web/src/routes/robots/[id]/expresiones/+page.svelte.
@MainActor
struct LabExpresiones: View {
    let modelo: ModeloRobot
    @State private var elegida = ""
    @State private var nombre = ""
    @State private var valores: ValoresRostro = Rostro.neutral
    @State private var referencia: ValoresRostro = Rostro.neutral
    @State private var extra = Extra()
    @State private var extraRef = Extra()
    @State private var lado = "ojo"
    @State private var grupo = "ojos"
    @State private var error = ""
    @State private var aviso = ""
    @State private var guardando = false

    struct Extra: Equatable { var movimiento = "ninguno", particula = "ninguna", parpadeo = "normal" }

    struct Grupo {
        let clave: String, nombre: String, icono: String, ojo: Bool
        let perillas: [(String, String)]
    }

    private let grupos: [Grupo] = [
        Grupo(clave: "ojos", nombre: "Ojos", icono: "eye", ojo: true, perillas: [("w", "Ancho"), ("h", "Alto"), ("r", "Redondez"), ("tilt", "Giro"), ("squash", "Aplastado")]),
        Grupo(clave: "parpados", nombre: "Párpados", icono: "eye.half.closed", ojo: true, perillas: [("lt", "Arriba"), ("lta", "Ángulo"), ("lb", "Abajo"), ("lba", "Ángulo")]),
        Grupo(clave: "adornos", nombre: "Adornos", icono: "heart", ojo: true,
              perillas: [("smile", "Feliz"), ("heart", "Corazón"), ("star", "Estrella"), ("cross", "Cruz"), ("ring", "Anillo"), ("pupil", "Pupila")]),
        Grupo(clave: "mirada", nombre: "Mirada", icono: "scope", ojo: false, perillas: [("ey", "Altura"), ("sep", "Separación"), ("fscale", "Tamaño"), ("ftilt", "Giro")]),
        Grupo(clave: "boca", nombre: "Boca", icono: "mouth", ojo: false, perillas: [("mcurve", "Sonrisa"), ("mo", "Abierta"), ("mw", "Ancha"), ("blush", "Cachetes")]),
        Grupo(clave: "efectos", nombre: "Efectos", icono: "bolt.fill", ojo: false,
              perillas: [("pulse", "Pulso"), ("beat", "Latido"), ("shake", "Temblor"), ("spin", "Remolino"), ("orbit", "Órbita"), ("glitch", "Glitch"), ("dim", "Apagado"), ("hue", "Rojo")]),
        Grupo(clave: "vida", nombre: "Gestos", icono: "figure.wave", ojo: false, perillas: []),
    ]

    private var propias: [String: Any] { modelo.config.expresiones.filter { ($0.value as? [String: Any])?["formas"] == nil } }
    private var nombres: [String] {
        let base = VidaBase.nombresCaras
        return base + propias.keys.filter { !base.contains($0) }.sorted()
    }
    private var configUsuario: String { modelo.config.paraDibujar }

    private var documento: [String: Any] {
        var d = Rostro.documento(valores, referencia: referencia)
        if extra.movimiento != extraRef.movimiento { d["movimiento"] = extra.movimiento }
        if extra.particula != extraRef.particula { d["particula"] = extra.particula }
        if extra.parpadeo != extraRef.parpadeo { d["parpadeo"] = extra.parpadeo }
        return d
    }

    /// Lo que se está armando, para dibujarlo vivo.
    private var configEnVivo: String {
        var c = ConfigDoc(texto: configUsuario)
        c.ponerExpresion(nombreDibujo, documento)
        return c.texto
    }

    private var nombreDibujo: String { nombreValido(nombre) ? nombre : "mi-cara" }
    private var esBase: Bool { VidaBase.expresiones[elegida] != nil }

    var body: some View {
        let cambios = documento.count
        VStack(alignment: .leading, spacing: 16) {
            galeria
            PantallaDibujada(config: configEnVivo, expresion: nombreDibujo, pantalla: modelo.pantalla, fps: 30, escala: 2)
                .aspectRatio(modelo.pantalla.redonda ? 1 : 320 / 172, contentMode: .fit)
                .clipShape(modelo.pantalla.redonda ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
                .padding(14)
                .chapa(radio: modelo.pantalla.redonda ? 200 : 30)
            BarraLab(nombre: $nombre, fijo: !elegida.isEmpty && esBase, enRobot: accionEnRobot, original: accionOriginal,
                     textoOriginal: esBase ? "Original" : "Borrar", guardar: { Task { await guardar() } },
                     textoGuardar: textoGuardar(cambios), puedeGuardar: !guardando && (cambios > 0 || elegida.isEmpty))
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
            PlacaNaranja(relleno: 14, radio: 28) {
                solapas
                Bandeja { controles }
            }
        }
        .onAppear { if elegida.isEmpty && nombre.isEmpty { elegir("contento") } }
    }

    private var accionEnRobot: (() -> Void)? {
        if elegida.isEmpty || !modelo.conectado { return nil }
        return { probarEnRobot() }
    }

    private var accionOriginal: (() -> Void)? {
        if elegida.isEmpty || propias[elegida] == nil { return nil }
        return { Task { await volverABase() } }
    }

    private func textoGuardar(_ cambios: Int) -> String {
        if guardando { return "Guardando…" }
        if !aviso.isEmpty { return aviso }
        return cambios > 0 ? "Guardar (\(cambios))" : "Guardar"
    }

    private static let lados: [(String, String)] = [("ojo", "Los dos"), ("izq", "Izq."), ("der", "Der.")]

    private var galeria: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { nueva() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.brasa)
                            .frame(width: 96, height: modelo.pantalla.redonda ? 96 : 52)
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(hex: 0x3A3632), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                        Text("NUEVA").font(Tipos.marca(9.5, .heavy)).foregroundStyle(Color.grisClaro)
                    }
                }
                .buttonStyle(.plain)
                ForEach(nombres, id: \.self) { n in
                    Button { elegir(n) } label: {
                        VStack(spacing: 6) {
                            MiniCara(nombre: n, config: configUsuario, pantalla: modelo.pantalla, ancho: 96)
                            HStack(spacing: 4) {
                                Text(n).font(Tipos.marca(9.5, .bold)).lineLimit(1)
                                if propias[n] != nil { Led(estado: .on, tamano: 6) }
                            }
                            .foregroundStyle(n == elegida ? Color.papel : Color.grisClaro)
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 12).fill(n == elegida ? Color.chapa : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(n == elegida ? Color.brasa : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var solapas: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(grupos, id: \.clave) { g in
                Button { grupo = g.clave } label: {
                    VStack(spacing: 6) {
                        Image(systemName: g.icono).font(.system(size: 16, weight: .semibold)).foregroundStyle(grupo == g.clave ? Color.brasa : Color.tinta)
                        Text(g.nombre.uppercased()).font(Tipos.angosta(9.5, .black)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(grupo == g.clave ? Color.papel : Color.tinta)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(EstiloTeclaModulo(elegido: grupo == g.clave))
            }
        }
    }

    @ViewBuilder private var controles: some View {
        let g = grupos.first { $0.clave == grupo } ?? grupos[0]
        if g.ojo {
            HStack(spacing: 6) {
                ForEach(LabExpresiones.lados, id: \.0) { k, t in
                    Llave(texto: t, prendida: lado == k, ancha: true) { lado = k }
                }
            }
        }
        if grupo == "mirada" {
            Pad(nombre: "Hacia dónde mira", x: valores["gx"] ?? 0, y: valores["gy"] ?? 0, minX: -0.3, maxX: 0.3, minY: -0.25, maxY: 0.25) { x, y in
                valores["gx"] = x
                valores["gy"] = y
            }
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
        }
        if grupo == "vida" {
            Grabado("Se mueve", color: Color.tinta.opacity(0.66))
            Chips(opciones: MOVIMIENTOS, elegida: extra.movimiento) { extra.movimiento = $0 }
            Grabado("Le sale", color: Color.tinta.opacity(0.66))
            Chips(opciones: ["ninguna"] + PARTICULAS, elegida: extra.particula, texto: { $0 == "ninguna" ? "—" : GLIFO[$0] ?? $0 }) { extra.particula = $0 }
            Grabado("Parpadea", color: Color.tinta.opacity(0.66))
            Chips(opciones: PARPADEOS, elegida: extra.parpadeo) { extra.parpadeo = $0 }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 18) {
                ForEach(g.perillas, id: \.0) { p, t in perilla(p, t, ojo: g.ojo) }
            }
        }
    }

    private func perilla(_ p: String, _ t: String, ojo: Bool) -> some View {
        let lim = LIMITES_PARAM[p] ?? (0, 1)
        let clave = ojo ? (lado == "der" ? "der.\(p)" : "izq.\(p)") : p
        return Perilla(nombre: t, valor: valores[clave] ?? lim.0, min: lim.0, max: lim.1, paso: 0.01, tamano: 54) { v in
            if !ojo {
                valores[p] = v
            } else {
                if lado != "der" { valores["izq.\(p)"] = v }
                if lado != "izq" { valores["der.\(p)"] = v }
            }
        }
    }

    // MARK: Acciones

    private func extraDe(_ d: [String: Any]?) -> Extra {
        Extra(movimiento: d?["movimiento"] as? String ?? "ninguno", particula: d?["particula"] as? String ?? "ninguna",
              parpadeo: d?["parpadeo"] as? String ?? "normal")
    }

    private func elegir(_ n: String) {
        error = ""
        aviso = ""
        elegida = n
        nombre = n
        let base = VidaBase.expresiones[n]
        referencia = base != nil ? Rostro.deFabrica(n) : Rostro.neutral
        var v = referencia
        let propia = propias[n] as? [String: Any]
        if let ext = propia?["extiende"] as? String { v = Rostro.deFabrica(ext) }
        if let propia { Rostro.aplicar(propia, a: &v) }
        valores = v
        extraRef = extraDe(base)
        var e = extraRef
        if let m = propia?["movimiento"] as? String { e.movimiento = m }
        if let p = propia?["particula"] as? String { e.particula = p }
        if let p = propia?["parpadeo"] as? String { e.parpadeo = p }
        extra = e
    }

    private func nueva() {
        var n = "mi-cara", k = 2
        while nombres.contains(n) { n = "mi-cara-\(k)"; k += 1 }
        let v = valores, e = extra
        elegida = ""
        nombre = n
        valores = v
        extra = e
        referencia = Rostro.neutral
        extraRef = Extra()
    }

    private func guardar() async {
        error = ""
        guard nombreValido(nombre) else { error = "Minúsculas, sin espacios."; return }
        let doc = documento
        var c = modelo.config
        if VidaBase.expresiones[nombre] != nil, doc.isEmpty { c.ponerExpresion(nombre, nil) } else { c.ponerExpresion(nombre, doc) }
        guardando = true
        let e = await modelo.guardarAhora(c)
        guardando = false
        if let e { error = e; return }
        elegida = nombre
        aviso = "Guardada"
        try? await Task.sleep(for: .seconds(2.5))
        aviso = ""
    }

    private func volverABase() async {
        var c = modelo.config
        c.ponerExpresion(elegida, nil)
        if let e = await modelo.guardarAhora(c) { error = e; return }
        elegir(nombres.contains(elegida) ? elegida : "neutral")
    }

    private func probarEnRobot() {
        let n = elegida
        Task {
            if let e = await modelo.comando(["expresion": n]) { error = e; return }
            try? await Task.sleep(for: .seconds(4))
            await modelo.comando(["expresion": ""])
        }
    }
}
