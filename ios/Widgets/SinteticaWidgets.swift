import ActivityKit
import SwiftUI
import WidgetKit

// Los widgets de la S1 (marca/diseno/App S1 Push y widgets.dc.html): su cara
// con su estado en la pantalla de inicio, lo que viene hoy, y el timer en la
// pantalla bloqueada y en la Dynamic Island. Leen la sesión del llavero
// compartido (Compartido.swift) y piden a la nube cada 15 minutos.

@main
struct SinteticaWidgets: WidgetBundle {
    var body: some Widget {
        SuS1Widget()
        HoyWidget()
        TimerEnVivoWidget()
    }
}

// MARK: - Colores (los de APP.md; la extensión no ve el Tema de la app)

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    static let naranja = Color(hex: 0xFF6A33)
    static let pantalla = Color(hex: 0x0B0A09)
    static let crema = Color(hex: 0xF5F2EC)
    static let noche = Color(hex: 0x151311)
}

private struct Tinta {
    let oscuro: Bool
    var fondo: Color { oscuro ? .noche : .crema }
    var texto: Color { oscuro ? .crema : .pantalla }
    var suave: Color { oscuro ? Color(hex: 0xB3ACA2) : Color(hex: 0x5C574F) }
    func led(_ e: EstadoWidget) -> Color {
        switch e {
        case .despierta: oscuro ? Color(hex: 0xC6F05A) : Color(hex: 0x658F0E)
        case .durmiendo: oscuro ? Color(hex: 0xB9A4FF) : Color(hex: 0x7A5FE0)
        case .sinConexion: Color(hex: 0x8A847B)
        }
    }
}

// MARK: - Datos

enum EstadoWidget: String {
    case despierta, durmiendo, sinConexion

    var texto: String {
        switch self {
        case .despierta: "Despierta"
        case .durmiendo: "Durmiendo"
        case .sinConexion: "Sin conexión"
        }
    }
}

struct CosaWidget: Hashable {
    let titulo: String
    let hora: String
}

struct EntradaS1: TimelineEntry {
    let date: Date
    let nombre: String
    let estado: EstadoWidget
    let cosas: [CosaWidget]
    let sinSesion: Bool

    static let ejemplo = EntradaS1(date: .now, nombre: "Ivy", estado: .despierta,
                                   cosas: [CosaWidget(titulo: "Dentista", hora: "10:00"), CosaWidget(titulo: "La pastilla", hora: "21:00")],
                                   sinSesion: false)
}

private struct Nube {
    let sesion: LlaveroCompartido.Sesion

    func pedir(_ ruta: String) async throws -> [String: Any] {
        guard let url = URL(string: sesion.servidor + ruta) else { throw URLError(.badURL) }
        var r = URLRequest(url: url, timeoutInterval: 12)
        r.setValue("Bearer " + sesion.token, forHTTPHeaderField: "Authorization")
        let (d, res) = try await URLSession.shared.data(for: r)
        guard (res as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw URLError(.badServerResponse) }
        return j
    }

    /// La S1 que se muestra: la conectada, o la primera.
    func entrada() async throws -> EntradaS1 {
        let bichos = (try await pedir("/v1/bichos")["bichos"] as? [[String: Any]]) ?? []
        guard let b = bichos.first(where: { $0["conectado"] as? Bool == true }) ?? bichos.first,
              let id = b["id"] as? String else {
            return EntradaS1(date: .now, nombre: "Tu S1", estado: .sinConexion, cosas: [], sinSesion: false)
        }
        let est = b["estado"] as? [String: Any]
        let apodo = (b["apodo"] as? String) ?? ""
        let nombre = apodo.isEmpty ? ((est?["nombre"] as? String) ?? "Tu S1") : apodo
        let estado: EstadoWidget = b["conectado"] as? Bool != true ? .sinConexion
            : (est?["dormido"] as? Bool == true ? .durmiendo : .despierta)
        let hoy = (try? await pedir("/v1/bichos/\(id)/hoy")["cosas"] as? [[String: Any]]) ?? []
        let cosas = hoy.prefix(3).map { CosaWidget(titulo: ($0["titulo"] as? String) ?? "", hora: ($0["hora"] as? String) ?? "") }
        return EntradaS1(date: .now, nombre: nombre, estado: estado, cosas: Array(cosas), sinSesion: false)
    }
}

struct ProveedorS1: TimelineProvider {
    func placeholder(in context: Context) -> EntradaS1 { .ejemplo }

    func getSnapshot(in context: Context, completion: @escaping (EntradaS1) -> Void) {
        completion(.ejemplo)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaS1>) -> Void) {
        Task {
            var e = EntradaS1(date: .now, nombre: "Tu S1", estado: .sinConexion, cosas: [], sinSesion: true)
            if let s = LlaveroCompartido.leer() {
                e = (try? await Nube(sesion: s).entrada())
                    ?? EntradaS1(date: .now, nombre: "Tu S1", estado: .sinConexion, cosas: [], sinSesion: false)
            }
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

// MARK: - Piezas

/// Su pantalla: el cuadrado negro con el borde naranja y los ojos.
struct CaraWidget: View {
    let estado: EstadoWidget
    var lado: CGFloat = 56

    var body: some View {
        let ojo = lado * 0.13
        RoundedRectangle(cornerRadius: lado * 0.24, style: .continuous)
            .fill(Color.pantalla)
            .overlay(RoundedRectangle(cornerRadius: lado * 0.24, style: .continuous).strokeBorder(Color.naranja, lineWidth: lado * 0.07))
            .overlay {
                HStack(spacing: lado * 0.16) {
                    ForEach(0..<2, id: \.self) { _ in
                        if estado == .durmiendo {
                            Capsule().fill(Color.naranja).frame(width: ojo * 1.6, height: ojo * 0.5)
                        } else {
                            Capsule().fill(estado == .sinConexion ? Color(hex: 0x8A847B) : .naranja)
                                .frame(width: ojo, height: lado * 0.3)
                        }
                    }
                }
            }
            .frame(width: lado, height: lado)
    }
}

private struct Chip: View {
    let estado: EstadoWidget
    let tinta: Tinta

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tinta.led(estado)).frame(width: 7, height: 7)
            Text(estado.texto).font(.system(size: 13, weight: .bold)).foregroundStyle(tinta.texto)
        }
    }
}

// MARK: - Su S1 (chico)

struct SuS1Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "su-s1", provider: ProveedorS1()) { e in
            VistaSuS1(e: e)
        }
        .configurationDisplayName("Su cara")
        .description("Tu S1 y cómo está.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct VistaSuS1: View {
    let e: EntradaS1
    @Environment(\.colorScheme) private var esquema
    @Environment(\.widgetFamily) private var familia

    var body: some View {
        let tinta = Tinta(oscuro: esquema == .dark)
        switch familia {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                CaraWidget(estado: e.estado, lado: 40)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text("\(e.nombre) · \(e.estado.texto)")
                .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 8) {
                CaraWidget(estado: e.estado, lado: 64)
                Spacer(minLength: 0)
                Text(e.sinSesion ? "Sintética" : e.nombre)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(tinta.texto).lineLimit(1)
                if e.sinSesion {
                    Text("Entrá en la app").font(.system(size: 13, weight: .bold)).foregroundStyle(tinta.suave)
                } else {
                    Chip(estado: e.estado, tinta: tinta)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { tinta.fondo }
            .widgetURL(URL(string: "sintetica://inicio"))
        }
    }
}

// MARK: - Hoy (mediano y rectangular)

struct HoyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "hoy", provider: ProveedorS1()) { e in
            VistaHoy(e: e)
        }
        .configurationDisplayName("Hoy")
        .description("Lo que viene hoy, con tu S1.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct VistaHoy: View {
    let e: EntradaS1
    @Environment(\.colorScheme) private var esquema
    @Environment(\.widgetFamily) private var familia

    var body: some View {
        let tinta = Tinta(oscuro: esquema == .dark)
        if familia == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.nombre).font(.system(size: 13, weight: .bold))
                if let c = e.cosas.first {
                    Text(c.hora.isEmpty ? c.titulo : "\(c.hora) \(c.titulo)").font(.system(size: 15, weight: .bold)).lineLimit(1)
                } else {
                    Text("Nada más por hoy").font(.system(size: 15, weight: .bold))
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    CaraWidget(estado: e.estado, lado: 72)
                    Chip(estado: e.estado, tinta: tinta)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hoy").font(.system(size: 17, weight: .bold)).foregroundStyle(tinta.texto)
                    if e.sinSesion {
                        Text("Entrá en la app").font(.system(size: 15, weight: .bold)).foregroundStyle(tinta.suave)
                    } else if e.cosas.isEmpty {
                        Text("Nada más por hoy").font(.system(size: 15, weight: .bold)).foregroundStyle(tinta.suave)
                    } else {
                        ForEach(e.cosas, id: \.self) { c in
                            HStack(spacing: 8) {
                                Text(c.titulo).font(.system(size: 15, weight: .bold)).foregroundStyle(tinta.texto).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(c.hora.isEmpty ? "Todo el día" : c.hora)
                                    .font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(tinta.suave)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .containerBackground(for: .widget) { tinta.fondo }
            .widgetURL(URL(string: "sintetica://hoy"))
        }
    }
}

// MARK: - El timer en vivo

struct TimerEnVivoWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAtributos.self) { ctx in
            HStack(spacing: 12) {
                CaraWidget(estado: .despierta, lado: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.nombre).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.crema)
                    Text(ctx.attributes.robot).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xB3ACA2))
                }
                Spacer()
                Cuenta(estado: ctx.state, tamano: 36)
            }
            .padding(16)
            .activityBackgroundTint(Color.noche)
            .activitySystemActionForegroundColor(.naranja)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CaraWidget(estado: .despierta, lado: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Cuenta(estado: ctx.state, tamano: 28)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ctx.attributes.nombre).font(.system(size: 15, weight: .bold))
                }
            } compactLeading: {
                CaraWidget(estado: .despierta, lado: 22)
            } compactTrailing: {
                Cuenta(estado: ctx.state, tamano: 15).frame(maxWidth: 52)
            } minimal: {
                CaraWidget(estado: .despierta, lado: 22)
            }
            .keylineTint(.naranja)
        }
    }
}

/// La cuenta regresiva (la anima el sistema) o lo que faltaba, en pausa.
private struct Cuenta: View {
    let estado: TimerAtributos.ContentState
    let tamano: CGFloat

    var body: some View {
        Group {
            if estado.pausado {
                Text(Duration.seconds(estado.restante).formatted(.time(pattern: .minuteSecond)))
            } else {
                Text(timerInterval: Date.now...max(estado.fin, .now), countsDown: true)
            }
        }
        .font(.system(size: tamano, weight: .bold).monospacedDigit())
        .foregroundStyle(Color.naranja)
        .multilineTextAlignment(.trailing)
    }
}
