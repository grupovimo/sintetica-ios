import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Un video elegido de la galería, copiado a un archivo temporal.
struct VideoElegido: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { v in SentTransferredFile(v.url) } importing: { r in
            let destino = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString).\(r.file.pathExtension)")
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.copyItem(at: r.file, to: destino)
            return VideoElegido(url: destino)
        }
    }
}

/// Lee lo que se eligió en la galería: una foto, un GIF o un video corto.
func fuenteDe(_ item: PhotosPickerItem) async -> ModeloRobot.Fuente? {
    if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }), let v = try? await item.loadTransferable(type: VideoElegido.self) {
        return .video(v.url)
    }
    if let d = try? await item.loadTransferable(type: Data.self) { return .datos(d) }
    return nil
}

/// Imágenes: ocho bahías para fotos, GIFs o videos cortos. Cada una se puede
/// sumar a lo que muestra o usar de protector de pantalla. Como
/// web/src/lib/consola/modulos/Imagenes.svelte.
struct ModImagenes: View {
    let modelo: ModeloRobot
    @State private var bahia = 0
    @State private var eligiendo = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            protector
            if !modelo.errorImagenes.isEmpty { AvisoConsola(texto: modelo.errorImagenes, error: true) }
            if let p = modelo.progreso, modelo.subiendo >= 0, p > 0 { ProgressView(value: p).tint(Color.tinta) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(0 ..< 8, id: \.self) { e in celda(e) }
            }
        }
        .photosPicker(isPresented: $eligiendo, selection: $item, matching: .any(of: [.images, .videos]))
        .onChange(of: item) { _, i in
            guard let i else { return }
            let e = bahia
            Task {
                if let f = await fuenteDe(i) { await modelo.subir(e, f) }
                item = nil
            }
        }
    }

    private var protector: some View {
        let c = modelo.config
        return Bandeja {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Grabado("Protector", color: Color.tinta.opacity(0.66))
                    Text(c.protector.map { String(format: "BAHÍA %02d", $0 + 1) } ?? "APAGADO").font(Tipos.marca(20, .black)).foregroundStyle(Color.tinta)
                }
                Spacer()
                if c.protector != nil {
                    Button { modelo.cambiar { $0.ponerProtector(nil) } } label: { Text("Apagar") }.tecla(.negra, chica: true)
                }
            }
            if c.protector != nil {
                let s = c.esperaProtector
                VisorMasMenos(rotulo: "Aparece tras", valor: s < 60 ? "\(s) s" : "\(s / 60) min", chicos: true,
                              menos: { modelo.cambiar { $0.moverEspera(-1) } }, mas: { modelo.cambiar { $0.moverEspera(1) } })
            }
        }
    }

    private func celda(_ e: Int) -> some View {
        let lleno = modelo.espacios.contains { $0.espacio == e }
        let cuadros = modelo.miniaturas[e] ?? []
        let c = modelo.config
        return VStack(spacing: 8) {
            Button { bahia = e; eligiendo = true } label: { hueco(e, lleno: lleno, cuadros: cuadros) }
                .buttonStyle(.plain)
                .disabled(modelo.subiendo >= 0)
                .accessibilityLabel(lleno ? "Bahía \(e + 1): cambiar" : "Bahía \(e + 1): subir")
            if lleno {
                HStack(spacing: 6) {
                    Llave(texto: "Lista", prendida: c.enLista(e), ancha: true) { let si = !c.enLista(e); modelo.cambiar { $0.mostrar(e, si) } }
                    Button { Task { await modelo.borrar(e) } } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true)
                        .accessibilityLabel("Borrar la bahía \(e + 1)")
                }
                Llave(texto: "Protector", prendida: c.protector == e, ancha: true) {
                    let si = c.protector != e
                    modelo.cambiar { $0.ponerProtector(si ? e : nil) }
                }
            }
        }
    }

    private func hueco(_ e: Int, lleno: Bool, cuadros: [UIImage]) -> some View {
        let redonda = modelo.producto.redonda
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.9), radius: 6, y: 3)))
            if !cuadros.isEmpty {
                ImagenAnimada(cuadros: cuadros, duraciones: modelo.duraciones[e] ?? [])
                    .clipShape(redonda ? AnyShape(Circle()) : AnyShape(Rectangle()))
                    .padding(redonda ? 8 : 0)
            } else if modelo.subiendo == e {
                ProgressView().tint(Color.brasa)
            } else if lleno {
                Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(Color.gris)
            } else {
                Mas(tamano: 40)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(String(format: "%02d", e + 1)).font(Tipos.marca(9, .heavy)).foregroundStyle(Color.gris)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.hundido.opacity(cuadros.isEmpty ? 0 : 0.75)))
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if cuadros.count > 1 {
                Text("GIF").font(Tipos.marca(9, .black)).foregroundStyle(Color.tinta).padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.naranja)).padding(8)
            }
        }
    }
}

/// Recordatorios: a la hora, el robot lo muestra en su pantalla hasta que lo
/// tocás. Los textos se cuentan en bytes (40), como el robot.
struct ModRecordatorios: View {
    let modelo: ModeloRobot

    var body: some View {
        let lista = modelo.config.recordatorios
        let orden = lista.indices.sorted { lista[$0].hora < lista[$1].hora }
        VStack(spacing: 14) {
            HStack {
                Grabado("\(lista.count) de \(MAX_RECORDATORIOS)", color: Color.tinta.opacity(0.66))
                Spacer()
                Button { modelo.cambiar { $0.recordatorios = $0.recordatorios + [Recordatorio.nuevo()] } } label: { Label("Nuevo", systemImage: "plus") }
                    .tecla(.negra).disabled(lista.count >= MAX_RECORDATORIOS)
            }
            if lista.isEmpty {
                Bandeja {
                    HStack(spacing: 16) {
                        Text("--:--").font(Tipos.digitos).foregroundStyle(Color.tinta.opacity(0.4))
                        Text("08:30 · Pastilla").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
                    }
                }
            }
            ForEach(orden, id: \.self) { i in
                FichaRecordatorio(modelo: modelo, indice: i, r: lista[i])
            }
        }
    }
}

private let CARAS_RECORDATORIO: [(String, String)] = [
    ("sorpresa", "Sorpresa"), ("contento", "Contento"), ("pensando", "Pensando"), ("guino", "Guiño"), ("enamorado", "Enamorado"), ("escuchando", "Atento"),
]

private struct FichaRecordatorio: View {
    let modelo: ModeloRobot
    let indice: Int
    let r: Recordatorio
    @State private var texto = ""

    private func cambiar(_ f: @escaping (inout Recordatorio) -> Void) {
        let i = indice
        modelo.cambiar { c in
            var l = c.recordatorios
            guard i < l.count else { return }
            f(&l[i])
            c.recordatorios = l
        }
    }

    private var hora: Binding<Date> {
        Binding(get: {
            let m = aMinutos(r.hora)
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            let h = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            cambiar { $0.hora = h }
        })
    }

    var body: some View {
        Bandeja {
            HStack(spacing: 12) {
                Visor(relleno: 10) {
                    Grabado("A las")
                    DatePicker("", selection: hora, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact).tint(Color.brasa).colorScheme(.dark)
                }
                .frame(width: 140)
                VStack(spacing: 8) {
                    Llave(texto: r.prendido ? "Activo" : "Apagado", prendida: r.prendido, ancha: true) {
                        cambiar { $0.activo = $0.activo == false ? nil : false }
                    }
                    if modelo.producto.tiene(.parlante) {
                        Llave(texto: "Suena", prendida: r.sonido != false, ancha: true) { cambiar { $0.sonido = $0.sonido == false ? nil : false } }
                    }
                }
            }
            CampoVisor(rotulo: "Te dice", texto: $texto, ayuda: "Tomar la pastilla", claro: true) {
                let v = cortarBytes(texto.trimmingCharacters(in: .whitespaces), MAX_TEXTO_RECORDATORIO)
                if v.isEmpty { texto = r.texto } else if v != r.texto { cambiar { $0.texto = v } }
            }
            .onChange(of: texto) { _, v in let c = cortarBytes(v, MAX_TEXTO_RECORDATORIO); if c != v { texto = c } }
            HStack(spacing: 5) {
                ForEach(DIAS_SEMANA, id: \.letra) { d in
                    Button { cambiar { $0.alternar(d.letra) } } label: { Text(d.letra) }
                        .buttonStyle(EstiloDia(prendido: r.tiene(d.letra)))
                        .accessibilityLabel(d.nombre)
                        .accessibilityAddTraits(r.tiene(d.letra) ? [.isSelected] : [])
                }
            }
            HStack {
                Menu {
                    ForEach(CARAS_RECORDATORIO, id: \.0) { k, t in
                        Button(t) { cambiar { $0.expresion = k == "sorpresa" ? nil : k } }
                    }
                } label: {
                    HStack(spacing: 8) {
                        MiniCara(nombre: r.expresion ?? "sorpresa", config: nil, pantalla: modelo.pantalla, ancho: 44)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.papel).padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
                }
                .accessibilityLabel("Cara")
                Spacer()
                Button {
                    let i = indice
                    modelo.cambiar { c in var l = c.recordatorios; if i < l.count { l.remove(at: i) }; c.recordatorios = l }
                } label: { Image(systemName: "trash") }.tecla(.negra, cuadrada: true).accessibilityLabel("Borrar")
            }
        }
        .opacity(r.prendido ? 1 : 0.6)
        .onAppear { texto = r.texto }
        .onChange(of: r.texto) { _, v in texto = v }
    }
}

/// Las teclitas de los días.
struct EstiloDia: ButtonStyle {
    let prendido: Bool
    func makeBody(configuration: Configuration) -> some View {
        let abajo = prendido || configuration.isPressed
        let forma = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let colores: [Color] = prendido ? [Color(hex: 0x2A2622), Color(hex: 0x151310)] : [Color(hex: 0xFBF9F5), Color(hex: 0xE6E0D6)]
        return configuration.label
            .font(Tipos.marca(13, .black))
            .foregroundStyle(prendido ? Color.papel : Color.tinta.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(forma.fill(LinearGradient(colors: colores, startPoint: .top, endPoint: .bottom)))
            .background(forma.fill(prendido ? Color.black : Color(hex: 0x8F887C)).offset(y: abajo ? 1 : 4))
            .offset(y: abajo ? 3 : 0)
            .padding(.bottom, 4)
    }
}
