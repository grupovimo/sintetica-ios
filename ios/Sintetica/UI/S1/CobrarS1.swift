import Foundation
import Observation
import SwiftUI
import UIKit

// 14 · Cobrar y 15 · Te pagaron: un cobro a mano con Mercado Pago (el QR sale
// en su pantalla y en la app) y el aviso cuando pagan.

/// Un cobro (GET /v1/cobros).
struct Cobro: Identifiable, Equatable {
    var codigo = "", concepto = "", quien = "", bicho = "", link = "", pagador = ""
    var monto = 0.0
    var creado: Date?
    var pagado: Date?
    var id: String { codigo }

    init(_ o: [String: Any]) {
        codigo = o["codigo"] as? String ?? ""
        monto = (o["monto"] as? NSNumber)?.doubleValue ?? 0
        concepto = o["concepto"] as? String ?? ""
        quien = o["quien"] as? String ?? ""
        bicho = o["bicho"] as? String ?? ""
        link = o["link"] as? String ?? ""
        creado = (o["creado"] as? String).flatMap(fechaISO)
        pagado = (o["pagado"] as? String).flatMap(fechaISO)
        pagador = o["pagador"] as? String ?? ""
    }
}

/// Un pago que acaba de llegar (el aviso "entrante" de tipo pago).
struct PagoRecibido: Equatable, Identifiable {
    let monto: String
    let de: String
    let cuando: Date
    var id: Date { cuando }
}


extension ApiSintetica {
    func cobros() async throws -> (conectado: Bool, cobros: [Cobro]) {
        let o = try await pedir("/v1/cobros")
        return (o["conectado"] as? Bool ?? false, (o["cobros"] as? [[String: Any]] ?? []).map(Cobro.init))
    }

    func cobrar(monto: Double, concepto: String, quien: String, bicho: String) async throws -> Cobro {
        Cobro(try await pedir("/v1/cobros", "POST", ["monto": monto, "concepto": concepto, "quien": quien, "bicho": bicho]))
    }
}

/// Los cobros de la cuenta, compartidos por Cobrar, Te pagaron y el diario.
@MainActor
@Observable
final class CobrosS1 {
    enum Fase: Equatable { case cargando, lista, error }
    var fase: Fase = .cargando
    var conectado = false
    var lista: [Cobro] = []

    func cargar() async {
        guard Cuenta.compartida.activa else { fase = .error; return }
        do {
            let r = try await Cuenta.compartida.api.cobros()
            conectado = r.conectado
            lista = r.cobros
            fase = .lista
        } catch {
            if fase != .lista { fase = .error }
        }
    }

    var pagados: [Cobro] { lista.filter { $0.pagado != nil }.sorted { ($0.pagado ?? .distantPast) > ($1.pagado ?? .distantPast) } }
}

/// Las teclas del teclado numérico (físicas, como las de la S1).
private let TECLAS_MONTO = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "borrar"]

/// 14 · Cobrar: el monto con el teclado, para quién y "Mostrar QR".
@MainActor
struct CobrarS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @Environment(\.openURL) private var abrir
    @State private var monto = ""
    @State private var quien = ""
    @State private var concepto = ""
    @State private var cobro: Cobro?
    @State private var armando = false
    @State private var error = ""
    @State private var conectando = false

    private var cobros: CobrosS1 { sesion.cobros }
    private var valor: Double { Double(monto) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Cobrar", sesion: sesion, atras: { ir(.cerrarModulo) }, conPantalla: false)
            if !sesion.modelo.esNube {
                ScrollView { SoloNube().padding(20) }
            } else {
                switch cobros.fase {
                case .cargando:
                    ScrollView { EstadoCargando(renglones: 3).padding(.horizontal, 20).padding(.top, 24) }
                case .error:
                    ScrollView {
                        EstadoError(texto: "No pude ver tus cobros.") { Task { await cobros.cargar() } }.padding(20)
                    }
                case .lista:
                    if !cobros.conectado { sinMercadoPago } else { cuerpo }
                }
            }
        }
        .background(FondoConsola())
        .task { await cobros.cargar() }
    }

    private var sinMercadoPago: some View {
        CuerpoConBoton {
            PantallaGrande { CaraDibujada(expresion: "pensando", config: sesion.modelo.config.paraDibujar) }
            HStack(spacing: 12) {
                FichaLogo(imagen: "logo-mercadopago")
                Text("Mercado Pago").font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
                Spacer()
            }
            .padding(.top, 24)
            if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.top, 12) }
        } boton: {
            BotonS1(conectando ? "Abriendo…" : "Conectar Mercado Pago") { conectarMP() }.disabled(conectando)
        }
    }

    private var cuerpo: some View {
        CuerpoConBoton {
            PantallaGrande {
                if let c = cobro {
                    PantallaQR(link: c.link, monto: pesos(c.monto))
                } else {
                    PantallaQR(link: "", monto: pesos(valor))
                }
            }
            Text(pesos(valor)).font(.system(size: 44, weight: .bold).monospacedDigit()).foregroundStyle(Color.s1Tinta)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .accessibilityLabel("Monto: \(pesos(valor))")
            CampoS1(ayuda: "Para quién", texto: $quien).padding(.top, 16)
                .onChange(of: quien) { _, v in if v.count > 60 { quien = String(v.prefix(60)) }; cobro = nil }
            CampoS1(ayuda: "Por qué (opcional)", texto: $concepto).padding(.top, 8)
                .onChange(of: concepto) { _, v in if v.count > 120 { concepto = String(v.prefix(120)) }; cobro = nil }
            teclado.padding(.top, 16)
            if let c = cobro {
                Seccion("El QR")
                VStack(spacing: 12) {
                    if let q = imagenQRNitida(c.link) {
                        Image(uiImage: q).interpolation(.none).resizable().scaledToFit()
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                            .frame(maxWidth: 260)
                            .accessibilityLabel("QR para pagar \(pesos(c.monto))")
                    }
                    ShareLink(item: c.link) { Text("Mandar el link") }.tecla(ancha: true)
                }
                .frame(maxWidth: .infinity)
            }
            if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.top, 12) }
            let ultimos = Array(cobros.lista.prefix(5))
            if !ultimos.isEmpty {
                Seccion("Últimos")
                VStack(spacing: 0) {
                    ForEach(ultimos) { c in
                        FilaS1(titulo: c.quien.isEmpty ? (c.concepto.isEmpty ? "Cobro" : c.concepto) : c.quien,
                               detalle: c.pagado != nil ? "Pagó \(hace(c.pagado))" : "Esperando",
                               valor: pesos(c.monto)) {
                            IconoEnCirculo(icono: c.pagado != nil ? .check : .cobrar)
                        }
                    }
                }
            }
        } boton: {
            BotonS1(armando ? "Armando…" : "Mostrar QR") { mostrar() }
                .disabled(armando || valor < 1 || valor > 10_000_000)
        }
    }

    private var teclado: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(TECLAS_MONTO, id: \.self) { k in
                Button { tocar(k) } label: {
                    Group {
                        if k == "borrar" {
                            Image(systemName: "delete.left").font(.system(size: 20, weight: .semibold))
                        } else {
                            Text(k).font(.system(size: 24, weight: .bold).monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EstiloRelieve())
                .accessibilityLabel(k == "borrar" ? "Borrar" : k)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: monto)
    }

    private func tocar(_ k: String) {
        cobro = nil
        if k == "borrar" { monto = String(monto.dropLast()); return }
        var n = monto + k
        while n.hasPrefix("0") { n.removeFirst() }
        if n.count <= 8 { monto = n }
    }

    private func mostrar() {
        armando = true
        error = ""
        let m = valor, q = quien.trimmingCharacters(in: .whitespaces), c = concepto.trimmingCharacters(in: .whitespaces)
        Task {
            defer { armando = false }
            do {
                cobro = try await Cuenta.compartida.api.cobrar(monto: m, concepto: c, quien: q, bicho: sesion.id)
                await cobros.cargar()
            } catch let e as ErrorApi where e.estado == 409 {
                cobros.conectado = false
            } catch let e as ErrorApi {
                error = e.detalle.isEmpty ? "No se pudo armar el cobro." : e.detalle
            } catch {
                self.error = "No se pudo armar el cobro."
            }
        }
    }

    private func conectarMP() {
        conectando = true
        error = ""
        Task {
            defer { conectando = false }
            do {
                if let u = URL(string: try await Cuenta.compartida.api.enlaceMercadoPago()), u.scheme != nil { abrir(u) } else { ir(.modulo(.avisos)) }
            } catch {
                ir(.modulo(.avisos))
            }
        }
    }
}

/// 15 · Te pagaron: su pantalla festejando, de quién, cuánto, cómo y cuándo;
/// abajo los de antes y "Cobrar otra vez".
@MainActor
struct TePagaronS1: View {
    let sesion: SesionS1
    var pago: PagoRecibido?
    let ir: (IrA) -> Void

    private var cobros: CobrosS1 { sesion.cobros }

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Te pagaron", sesion: sesion, atras: { ir(.cerrarModulo) }, conPantalla: false)
            switch cobros.fase {
            case .cargando where pago == nil:
                ScrollView { EstadoCargando(renglones: 3).padding(.horizontal, 20).padding(.top, 24) }
            case .error where pago == nil:
                ScrollView { EstadoError(texto: "No pude ver tus cobros.") { Task { await cobros.cargar() } }.padding(20) }
            default:
                cuerpo
            }
        }
        .background(FondoConsola())
        .task { await cobros.cargar() }
    }

    private var ultimo: (monto: String, de: String, hora: Date?)? {
        if let p = pago { return (p.monto, p.de, p.cuando) }
        if let c = cobros.pagados.first { return (pesos(c.monto), c.pagador.isEmpty ? c.quien : c.pagador, c.pagado) }
        return nil
    }

    private var cuerpo: some View {
        CuerpoConBoton {
            if let u = ultimo {
                PantallaGrande { PantallaPagado(monto: u.monto, de: u.de, config: sesion.modelo.config.paraDibujar) }
                VStack(spacing: 0) {
                    FilaS1(titulo: "De", valor: u.de.isEmpty ? "—" : u.de) { EmptyView() }
                    FilaS1(titulo: "Monto", valor: u.monto) { EmptyView() }
                    FilaS1(titulo: "Medio", valor: "Mercado Pago") { EmptyView() }
                    FilaS1(titulo: "Hora", valor: u.hora.map { Self.hora.string(from: $0) } ?? "—") { EmptyView() }
                }
                .padding(.top, 24)
            } else {
                EstadoVacio(texto: "Todavía no te pagaron.", expresion: "pensando")
            }
            let antes = Array(cobros.pagados.dropFirst(pago == nil ? 1 : 0).prefix(10))
            if !antes.isEmpty {
                Seccion("Antes")
                VStack(spacing: 0) {
                    ForEach(antes) { c in
                        FilaS1(titulo: c.pagador.isEmpty ? (c.quien.isEmpty ? "Alguien" : c.quien) : c.pagador,
                               detalle: c.pagado.map { Self.cuando($0) } ?? "", valor: pesos(c.monto)) { IconoEnCirculo(icono: .check) }
                    }
                }
            }
        } boton: {
            BotonS1("Cobrar otra vez") { ir(.modulo(.cobrar)) }
        }
    }

    static let hora: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func cuando(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoy · \(hora.string(from: d))" }
        if cal.isDateInYesterday(d) { return "Ayer · \(hora.string(from: d))" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "EEEE · HH:mm"
        return f.string(from: d).capitalized
    }
}
