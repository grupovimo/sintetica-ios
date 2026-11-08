import PhotosUI
import SwiftUI

/// Encender un robot: el onboarding de la primera vez. Cuatro pasos (nombre,
/// carácter, su día y una primera imagen), con el robot arriba reaccionando a
/// cada elección. Como web/src/routes/robots/[id]/encender/+page.svelte.
@MainActor
struct EncenderVista: View {
    let modelo: ModeloRobot
    @Environment(\.dismiss) private var cerrar
    @State private var paso = 1
    @State private var nombre = ""
    @State private var tuNombre = ""
    @State private var dia = 0
    @State private var mes = 0
    @State private var preset = "picaro"
    @State private var despierta = "08:00"
    @State private var duerme = "23:30"
    @State private var item: PhotosPickerItem?
    @State private var foto: ModeloRobot.Fuente?
    @State private var vistaFoto: UIImage?
    @State private var protector = false
    @State private var error = ""
    @State private var encendiendo = false

    private let pasos = ["Nombre", "Carácter", "Su día", "Foto"]
    private static let caraDePreset: [String: String] = [
        "dormilon": "cansado", "grunon": "grunon", "timido": "verguenza", "carinoso": "enamorado", "electrico": "emocionado", "curioso": "curioso",
    ]
    private var quien: String { nombre.trimmingCharacters(in: .whitespaces).isEmpty ? "Tu robot" : nombre.trimmingCharacters(in: .whitespaces) }

    private var cara: String {
        switch paso {
        case 1: "contento"
        case 2: EncenderVista.caraDePreset[preset] ?? "guino"
        case 3: "dormido"
        default: "enamorado"
        }
    }

    private var dice: String {
        switch paso {
        case 1: "\(quien) se despierta"
        case 2: "\(quien) prueba ser \((NOMBRES_PRESET[preset] ?? preset).lowercased())"
        case 3: "De noche, \(quien) duerme"
        default: "\(quien) ya te quiere"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                progreso
                Producto(modelo: modelo.producto, etiqueta: dice, radio: 28) {
                    PantallaDibujada(config: borrador.paraDibujar, expresion: cara, pantalla: modelo.pantalla, fps: 20)
                }
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                Grabado("Paso \(paso) de 4", color: .brasa)
                contenido
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                botones
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FondoConsola())
        .animation(.easeOut(duration: 0.2), value: paso)
        .onAppear(perform: arrancar)
        .onChange(of: item) { _, i in
            guard let i else { return }
            Task {
                foto = await fuenteDe(i)
                if case let .datos(d)? = foto { vistaFoto = UIImage(data: d) } else { vistaFoto = nil }
            }
        }
    }

    private var borrador: ConfigDoc {
        var c = modelo.config
        c.aV2()
        if !nombre.trimmingCharacters(in: .whitespaces).isEmpty { c.nombre = cortarBytes(quien, 24) }
        c.ponerPreset(preset)
        c.ponerHorario(despierta: despierta, duerme: duerme)
        return c
    }

    private func arrancar() {
        let c = modelo.config
        nombre = modelo.nombre == "Tu robot" ? "" : modelo.nombre
        tuNombre = c.nombreDueno
        if c.tienePreset { preset = c.preset }
        despierta = c.despierta
        duerme = c.duerme
        let p = partesCumple(c.cumpleDueno)
        mes = p.mes
        dia = p.dia
    }

    private var progreso: some View {
        HStack(spacing: 14) {
            ForEach(Array(pasos.enumerated()), id: \.offset) { i, p in
                HStack(spacing: 6) {
                    Led(estado: i < paso ? .on : .apagado)
                    if i + 1 == paso { Grabado(p, color: .papel) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.chapa))
    }

    @ViewBuilder private var contenido: some View {
        switch paso {
        case 1:
            Titular("Ponele nombre.")
            CampoVisor(rotulo: "Se llama", texto: $nombre, ayuda: "Lucho", tamano: 36)
            CampoVisor(rotulo: "Vos te llamás", texto: $tuNombre, ayuda: "Tu nombre", claro: true)
            SelectorCumple(rotulo: "Tu cumple", valor: mes > 0 && dia > 0 ? String(format: "%02d-%02d", mes, dia) : nil) { m, d in mes = m; dia = d }
        case 2:
            Titular("¿Cómo es?")
            PlacaNaranja {
                Dial(valor: preset) { preset = $0 }.frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    Text((NOMBRES_PRESET[preset] ?? preset).uppercased()).font(Tipos.marca(34, .black)).foregroundStyle(Color.tinta)
                    Text(DICE_PRESET[preset] ?? "").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }
        case 3:
            Titular("Su día.")
            VisorMasMenos(rotulo: "Se despierta", valor: despierta, menos: { mover(true, -15) }, mas: { mover(true, 15) })
            VisorMasMenos(rotulo: "Se duerme", valor: duerme, menos: { mover(false, -15) }, mas: { mover(false, 15) })
        default:
            Titular("¿Una foto?")
            PhotosPicker(selection: $item, matching: .any(of: [.images, .videos])) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.9), radius: 6, y: 3)))
                    if let v = vistaFoto {
                        Image(uiImage: v).resizable().scaledToFit()
                    } else if foto != nil {
                        Image(systemName: "film").font(.system(size: 40)).foregroundStyle(Color.brasa)
                    } else {
                        VStack(spacing: 14) {
                            Mas(tamano: 64)
                            Text("FOTO, GIF O VIDEO").font(Tipos.marca(14, .black)).foregroundStyle(Color.papel)
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
            Llave(texto: "Protector de pantalla", prendida: protector, ancha: true) { protector.toggle() }
        }
    }

    private func mover(_ esDespierta: Bool, _ d: Int) {
        if esDespierta {
            let n = sumarMinutos(despierta, d)
            if n != duerme { despierta = n }
        } else {
            let n = sumarMinutos(duerme, d)
            if n != despierta { duerme = n }
        }
    }

    private var botones: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if paso > 1 { Button { paso -= 1 } label: { Image(systemName: "chevron.left") }.tecla(cuadrada: true).accessibilityLabel("Atrás") }
                if paso < 4 {
                    Button { paso += 1 } label: { Text("Siguiente") }.tecla(.naranja, ancha: true)
                } else {
                    Button { encender() } label: { Text(encendiendo ? "Encendiendo…" : "Encender a \(quien)") }.tecla(.naranja, ancha: true).disabled(encendiendo)
                }
            }
            Button { modelo.marcarEncendido(); cerrar() } label: { Text("Más tarde") }.tecla(.negra, chica: true)
        }
    }

    private func encender() {
        encendiendo = true
        error = ""
        Task {
            var c = borrador
            c.ponerNombreDueno(tuNombre)
            if mes > 0, dia > 0 { c.ponerCumple(robot: false, mes: mes, dia: dia) }
            if !nombre.trimmingCharacters(in: .whitespaces).isEmpty, modelo.esNube {
                if let e = await modelo.ponerApodo(quien) { error = e; encendiendo = false; return }
            }
            if let f = foto {
                await modelo.subir(0, f)
                if !modelo.errorImagenes.isEmpty { error = modelo.errorImagenes; encendiendo = false; return }
                c.mostrar(0, !protector)
                if protector { c.ponerProtector(0) }
            }
            if let e = await modelo.guardarAhora(c) {
                error = e
                encendiendo = false
                return
            }
            modelo.marcarEncendido()
            cerrar()
        }
    }
}
