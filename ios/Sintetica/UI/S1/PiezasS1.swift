import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// Más piezas del sistema S1 (App S1 Sistema): integraciones, filas con
// toggle, el cuerpo con el botón fijo y lo que muestra su pantalla grande.

/// Un logo de integración en su ficha blanca de 48 (o del tamaño que sea).
struct FichaLogo: View {
    let imagen: String
    var tamano: CGFloat = 48

    var body: some View {
        Image(imagen).resizable().renderingMode(.original).scaledToFit()
            .frame(width: tamano * 0.58, height: tamano * 0.58)
            .frame(width: tamano, height: tamano)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.s1Linea, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// El estado de una integración: "Conectada" (contorno y check) o la tecla
/// "Conectar". Nunca un toggle (APP.md, Integración).
struct EstadoIntegracion: View {
    let conectada: Bool
    var ocupado = false
    let conectar: () -> Void

    var body: some View {
        if conectada {
            HStack(spacing: 6) {
                IconoS1(.check, tamano: 16)
                Text("Conectada").font(S1Tipo.captionFuerte)
            }
            .foregroundStyle(Color.s1Tinta)
            .padding(.horizontal, 12).frame(height: 32)
            .overlay(Capsule().strokeBorder(Color.s1Linea, lineWidth: 1))
            .accessibilityElement(children: .combine)
        } else {
            Button(action: conectar) { Text(ocupado ? "…" : "Conectar") }
                .tecla(chica: true)
                .disabled(ocupado)
        }
    }
}

/// Una fila de integración: el logo, su nombre, para qué sirve y su estado.
struct FilaIntegracion: View {
    let logo: String
    let nombre: String
    let detalle: String
    let conectada: Bool
    var ocupado = false
    let conectar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FichaLogo(imagen: logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                if !detalle.isEmpty { Text(detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1) }
            }
            Spacer(minLength: 8)
            EstadoIntegracion(conectada: conectada, ocupado: ocupado, conectar: conectar)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
    }
}

/// Un renglón con un toggle a la derecha (título y detalle a la izquierda).
struct FilaToggle: View {
    let titulo: String
    var detalle = ""
    let prendido: Bool
    let alternar: () -> Void

    var body: some View {
        Button(action: alternar) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(2)
                    if !detalle.isEmpty { Text(detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(2) }
                }
                Spacer(minLength: 8)
                Interruptor(prendido: prendido)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(prendido ? "Prendido" : "Apagado")
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.selection, trigger: prendido)
    }
}

/// Un renglón con − el valor + (el brillo, el volumen, los minutos).
struct FilaPasos: View {
    let titulo: String
    let valor: String
    var puedeMenos = true
    var puedeMas = true
    let menos: () -> Void
    let mas: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: menos) { IconoS1(.menos, tamano: 20) }.tecla(cuadrada: true).disabled(!puedeMenos)
                .accessibilityLabel("\(titulo): menos")
            Text(valor).font(S1Tipo.seccion.monospacedDigit()).foregroundStyle(Color.s1Tinta)
                .frame(minWidth: 44)
                .accessibilityLabel("\(titulo): \(valor)")
            Button(action: mas) { IconoS1(.sumar, tamano: 20) }.tecla(cuadrada: true).disabled(!puedeMas)
                .accessibilityLabel("\(titulo): más")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
    }
}

/// Una tarjeta (superficie, radio 20).
struct TarjetaS1<Contenido: View>: View {
    var relleno: CGFloat = 16
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
    }
}

/// El cuerpo de una pantalla con un botón fijo abajo (APP.md, regla 1).
struct CuerpoConBoton<Contenido: View, Boton: View>: View {
    @ViewBuilder let contenido: Contenido
    @ViewBuilder let boton: Boton

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { contenido }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, AIRE_BOTON_FIJO)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            BotonFijo { boton }
        }
    }
}

/// Un campo de 48 (el del sistema), sin rótulo.
struct CampoS1: View {
    let ayuda: String
    @Binding var texto: String
    var teclado: UIKeyboardType = .default
    var alMandar: () -> Void = {}
    @FocusState private var enfocado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        TextField("", text: $texto, prompt: Text(ayuda).foregroundColor(Color.s1Tinta3))
            .font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).tint(Color.s1Naranja)
            .keyboardType(teclado)
            .focused($enfocado)
            .submitLabel(.done)
            .onSubmit(alMandar)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(forma.fill(Color.s1Campo))
            .overlay(forma.strokeBorder(enfocado ? Color.s1Tinta : Color.s1Linea, lineWidth: enfocado ? 2 : 1))
    }
}

/// La inicial en un círculo (los amigos, la familia, tu perfil).
struct Inicial: View {
    let nombre: String
    var tamano: CGFloat = 48
    var body: some View {
        Text(String(nombre.trimmingCharacters(in: .whitespaces).first ?? "·").uppercased())
            .font(.system(size: tamano * 0.4, weight: .bold)).foregroundStyle(Color.s1InvTexto)
            .frame(width: tamano, height: tamano)
            .background(Circle().fill(Color.s1Inv))
            .accessibilityHidden(true)
    }
}

// --- Lo que muestra su pantalla (s1-pantalla.js) ---

/// La letra de adentro de su pantalla (Nunito no viene: la redondeada del sistema).
func letraPantalla(_ tamano: CGFloat) -> Font { .system(size: tamano, weight: .heavy, design: .rounded) }

/// "09:05" o "1:02:05".
func mmss(_ s: Int) -> String {
    let s = max(0, s)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
    return String(format: "%02d:%02d", s / 60, s % 60)
}

/// El timer en su pantalla: el anillo que se vacía y los minutos.
struct PantallaTimer: View {
    let restante: Int
    let total: Int
    var etiqueta = ""
    var pausado = false
    var listo = false

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            let fraccion = total > 0 ? Double(restante) / Double(total) : 0
            ZStack {
                Color.s1Pantalla
                Circle().stroke(Color.white.opacity(0.12), lineWidth: max(2, lado * 0.06))
                    .padding(lado * 0.1)
                Circle().trim(from: 0, to: listo ? 1 : fraccion)
                    .stroke(Color.s1Naranja, style: StrokeStyle(lineWidth: max(2, lado * 0.06), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lado * 0.1)
                    .animation(.linear(duration: 0.9), value: restante)
                VStack(spacing: lado * 0.02) {
                    Text(listo ? "¡Listo!" : mmss(restante)).font(letraPantalla(lado * (listo ? 0.17 : 0.2)).monospacedDigit())
                        .foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.5)
                    if lado >= 100, !etiqueta.isEmpty || pausado {
                        Text(pausado ? "En pausa" : etiqueta).font(letraPantalla(max(13, lado * 0.08)))
                            .foregroundStyle(Color.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(lado * 0.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(listo ? "Timer listo" : "Timer: quedan \(mmss(restante))")
    }
}

/// El QR (CoreImage) de un link, nítido.
func imagenQRNitida(_ texto: String, lado: CGFloat = 512) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(texto.utf8)
    f.correctionLevel = "M"
    guard let salida = f.outputImage else { return nil }
    let k = lado / max(1, salida.extent.width)
    let grande = salida.transformed(by: CGAffineTransform(scaleX: k, y: k))
    guard let cg = CIContext().createCGImage(grande, from: grande.extent) else { return nil }
    return UIImage(cgImage: cg)
}

/// El cobro en su pantalla: el monto y el QR.
struct PantallaQR: View {
    let link: String
    let monto: String

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            ZStack {
                Color.s1Pantalla
                VStack(spacing: lado * 0.04) {
                    if let q = imagenQRNitida(link.isEmpty ? "https://sintetica.grupovimo.com.ar" : link) {
                        Image(uiImage: q).interpolation(.none).resizable().scaledToFit()
                            .padding(lado * 0.035)
                            .background(RoundedRectangle(cornerRadius: lado * 0.04).fill(Color.white))
                            .frame(width: lado * 0.62, height: lado * 0.62)
                            .opacity(link.isEmpty ? 0.25 : 1)
                    }
                    Text(monto).font(letraPantalla(max(13, lado * 0.11)).monospacedDigit()).foregroundStyle(Color.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(lado * 0.08)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QR de \(monto)")
    }
}

/// Te pagaron: la cara contenta, el monto y de quién.
struct PantallaPagado: View {
    let monto: String
    var de = ""
    var config: String?

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            ZStack {
                CaraDibujada(expresion: "emocionado", config: config)
                VStack(spacing: 2) {
                    Spacer()
                    Text(monto).font(letraPantalla(max(13, lado * 0.13)).monospacedDigit()).foregroundStyle(Color.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if lado >= 100, !de.isEmpty {
                        Text(de).font(letraPantalla(max(13, lado * 0.08))).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                    }
                }
                .padding(.bottom, lado * 0.08)
                .padding(.horizontal, lado * 0.06)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Te pagaron \(monto)")
    }
}

/// La pastilla en su pantalla (Cuidado): el ícono y la hora.
struct PantallaPastilla: View {
    let hora: String

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            ZStack {
                Color.s1Pantalla
                VStack(spacing: lado * 0.05) {
                    Image(systemName: "pills.fill").font(.system(size: lado * 0.3, weight: .bold)).foregroundStyle(Color.s1Naranja)
                    Text(hora).font(letraPantalla(max(13, lado * 0.16)).monospacedDigit()).foregroundStyle(Color.white).lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("La pastilla a las \(hora)")
    }
}

/// Una lista en su pantalla (Listas): los últimos tres.
struct PantallaLista: View {
    let titulo: String
    let items: [String]

    var body: some View {
        GeometryReader { g in
            let lado = min(g.size.width, g.size.height)
            ZStack(alignment: .topLeading) {
                Color.s1Pantalla
                VStack(alignment: .leading, spacing: lado * 0.03) {
                    Text(titulo).font(letraPantalla(max(13, lado * 0.14))).foregroundStyle(Color.s1Naranja).lineLimit(1).minimumScaleFactor(0.5)
                    if lado >= 100 {
                        ForEach(Array(items.suffix(3).enumerated()), id: \.offset) { _, t in
                            Text(t).font(letraPantalla(max(13, lado * 0.1))).foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    } else {
                        Text("\(items.count)").font(letraPantalla(max(13, lado * 0.3))).foregroundStyle(Color.white)
                    }
                }
                .padding(lado * 0.12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titulo): \(items.joined(separator: ", "))")
    }
}

/// Su pantalla de 160 (las pantallas de detalle), con lo que tenga que mostrar.
struct PantallaGrande<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido
    var body: some View {
        MarcoPantalla(tamano: .detalle) { contenido }
            .frame(maxWidth: .infinity)
    }
}

/// La tecla de una tarjeta que se elige (los modos, para quién es): con foto
/// o sin ella; elegida = borde de 2 en tinta.
struct TarjetaElegible<Contenido: View>: View {
    let elegida: Bool
    let accion: () -> Void
    @ViewBuilder let contenido: Contenido

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: accion) {
            contenido
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(forma.fill(elegida ? Color.s1Inv : Color.s1Superficie))
                .clipShape(forma)
                .overlay(forma.strokeBorder(elegida ? Color.s1Inv : Color.clear, lineWidth: 2))
                .contentShape(forma)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegida ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: elegida)
    }
}

/// "$12.000" (sin centavos si no hay).
func pesos(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "es_AR")
    f.maximumFractionDigits = v == v.rounded() ? 0 : 2
    f.minimumFractionDigits = v == v.rounded() ? 0 : 2
    return "$" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
}
