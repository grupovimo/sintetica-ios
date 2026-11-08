import SwiftUI

/// Un robot en el dock: de la cuenta (por la nube) o solo vinculado a este celu.
struct RobotDock: Identifiable, Equatable {
    let id: String
    var nombre: String
    var perfil: String
    var virtual: Bool
    var conectado: Bool
    var ultimaConexion: Date?
    var estado: Estado?
    var soloCerca: Bool
    var config: String?

    var pantalla: Pantalla { pantallaDe(perfil: perfil, estado: estado) }
    var producto: ModeloProducto { ModeloProducto.de(perfil: perfil, virtual: virtual, pantalla: pantalla) }
}

/// Mis robots: el dock con cada uno (su foto real, la cara en vivo, cómo
/// está y cuánta batería tiene) y una bahía libre para sumar otro. Como
/// web/src/routes/robots/+page.svelte.
@MainActor
struct MisRobots: View {
    @Binding var ruta: [Ruta]
    private var cuenta = Cuenta.compartida
    private var vinculados = Vinculados.compartidos
    private var enVivo = EnVivo.compartido
    @State private var nube: [RobotNube] = []
    @State private var configs: [String: String] = [:]
    @State private var cargando = true
    @State private var error = ""
    @State private var sumando = false
    @State private var oyente: UUID?

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    private var robots: [RobotDock] {
        var l: [RobotDock] = nube.map { (r: RobotNube) -> RobotDock in
            RobotDock(id: r.id, nombre: nombreDe(r), perfil: r.perfil, virtual: r.virtual, conectado: r.conectado,
                      ultimaConexion: r.ultimaConexion, estado: r.estado, soloCerca: false, config: configs[r.id])
        }
        for v in vinculados.todos where !l.contains(where: { $0.id == v.id }) {
            l.append(RobotDock(id: v.id, nombre: v.nombre == "bicho" ? "Tu robot" : v.nombre, perfil: "", virtual: false, conectado: false,
                               ultimaConexion: nil, estado: nil, soloCerca: true, config: nil))
        }
        return l
    }

    private func nombreDe(_ r: RobotNube) -> String {
        if !r.apodo.isEmpty { return r.apodo }
        if let c = configs[r.id], let n = ConfigDoc(texto: c).nombre, !n.isEmpty { return n }
        if let n = r.estado?.nombre, !n.isEmpty, n != "bicho" { return n }
        return "Sin nombre"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                barra
                encabezado
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 24) {
                    ForEach(robots) { r in
                        Button { ruta.append(.robot(r.id)) } label: { Bahia(robot: r) }
                            .buttonStyle(.plain)
                    }
                    Button { sumando = true } label: { BahiaLibre() }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .background(FondoConsola())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await cargar() }
        .task(id: cuenta.activa) { await cargar() }
        .onAppear { oyente = enVivo.escuchar { e in recibir(e) } }
        .onDisappear { if let o = oyente { enVivo.dejar(o) } }
        .sheet(isPresented: $sumando) { SumarRobot(ruta: $ruta, cerrar: { sumando = false }) }
    }

    private var barra: some View {
        HStack {
            HStack(spacing: 10) {
                Marca()
                Text("SINTÉTICA").font(Tipos.marca(20, .black)).tracking(-0.4).foregroundStyle(Color.papel)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button { ruta.append(.cuenta) } label: {
                HStack(spacing: 8) {
                    Led(estado: !cuenta.activa ? .apagado : enVivo.conectado ? .verde : .ambar)
                    Text(cuenta.activa ? (cuenta.email.split(separator: "@").first.map(String.init) ?? "Cuenta") : "Entrar")
                }
            }
            .tecla(.negra, chica: true)
        }
        .padding(.top, 8)
    }

    private var encabezado: some View {
        let enLinea = robots.filter(\.conectado).count
        let n = robots.count
        return VStack(alignment: .leading, spacing: 12) {
            Grabado(cargando ? "Buscando…" : "\(n) \(n == 1 ? "robot" : "robots") · \(enLinea) en línea", color: .brasa)
            HStack(alignment: .bottom) {
                Titular("Mis robots", tamano: 44)
                Spacer(minLength: 8)
                Button { sumando = true } label: { Image(systemName: "plus") }.tecla(.naranja, cuadrada: true)
                    .accessibilityLabel("Sumar un robot")
            }
        }
    }

    private func cargar() async {
        defer { cargando = false }
        guard cuenta.activa else { nube = []; return }
        do {
            nube = try await cuenta.api.robots()
            error = ""
            for r in nube { Task { await cargarConfig(r.id) } }
        } catch let e as ErrorApi where e.estado == 401 {
            cuenta.salir()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cargarConfig(_ id: String) async {
        guard let c = try? await cuenta.api.config(id) else { return }
        configs[id] = ConfigDoc(texto: c.texto).paraDibujar
    }

    private func recibir(_ e: EventoNube) {
        if e.tipo == "bicho", e.datos["accion"] as? String != "actual" { Task { await cargar() }; return }
        guard let i = nube.firstIndex(where: { $0.id == e.bicho }) else { return }
        switch e.tipo {
        case "estado": if let x = estadoDeJSON(e.datos) { nube[i].estado = x }
        case "conexion": nube[i].conectado = e.datos["conectado"] as? Bool ?? false
        case "config": Task { await cargarConfig(e.bicho) }
        case "bicho": if let b = e.datos["bicho"] as? [String: Any] { nube[i] = RobotNube(b) }
        default: break
        }
    }
}

/// Una bahía del dock.
private struct Bahia: View {
    let robot: RobotDock

    private var led: EstadoLed {
        if robot.soloCerca { return .on }
        if !robot.conectado { return .apagado }
        return robot.estado?.dormido == true ? .ambar : .verde
    }

    private var detalle: String {
        if robot.soloCerca { return "Por Bluetooth" }
        return robot.conectado ? animoDe(robot.estado, conectado: true) : "Visto \(hace(robot.ultimaConexion))"
    }

    var body: some View {
        let m = robot.producto
        let bat = robot.estado?.bateria
        VStack(alignment: .leading, spacing: 0) {
            Producto(modelo: m, apagado: !robot.conectado && !robot.soloCerca, radio: 22) {
                PantallaDibujada(config: robot.config, expresion: robot.estado?.expresion ?? "neutral", pantalla: robot.pantalla)
            }
            .overlay(alignment: .topLeading) { sello.padding(14) }
            .padding([.horizontal, .top], 12)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Grabado("\(m.nombre) \(numeroDe(robot.id))\(robot.virtual ? " · virtual" : "")")
                    Spacer()
                    Led(estado: led)
                }
                Text(robot.nombre.uppercased()).font(Tipos.marca(32, .black)).tracking(-1).foregroundStyle(Color.papel)
                    .lineLimit(1).minimumScaleFactor(0.5)
                HStack {
                    Text(detalle).font(Tipos.marca(13, .bold)).foregroundStyle(robot.conectado ? Color.hueso : Color.gris)
                    Spacer()
                    Text(bat.map { "\($0)%" } ?? "—").font(Tipos.marca(14, .black).monospacedDigit())
                        .foregroundStyle(bat == nil ? Color(hex: 0x6B645B) : Color.brasa)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.8), radius: 3, y: 2))))
                }
                BarraCarga(bateria: bat, viva: robot.conectado)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
        }
        .chapa(radio: 32)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abrir la consola")
    }

    @ViewBuilder private var sello: some View {
        if robot.estado?.dormido == true, robot.conectado {
            etiqueta("Durmiendo", icono: "moon.fill")
        } else if !robot.conectado, !robot.soloCerca {
            etiqueta("Fuera de alcance", icono: nil)
        }
    }

    private func etiqueta(_ t: String, icono: String?) -> some View {
        HStack(spacing: 6) {
            if let icono { Image(systemName: icono).font(.system(size: 11)) }
            Text(t.uppercased()).font(Tipos.marca(10.5, .heavy)).tracking(1.2)
        }
        .foregroundStyle(Color.grisClaro)
        .padding(.horizontal, 12).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.hundido.opacity(0.82)))
    }
}

struct BarraCarga: View {
    let bateria: Int?
    var viva = true
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hundido)
                if let b = bateria {
                    Capsule()
                        .fill(b < 15 ? AnyShapeStyle(Color.rojo) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF2541A), Color.brasa], startPoint: .leading, endPoint: .trailing)))
                        .frame(width: g.size.width * CGFloat(b) / 100)
                        .shadow(color: viva ? Color.led : .clear, radius: 4)
                }
            }
        }
        .frame(height: 6)
        .accessibilityLabel(bateria.map { "Batería \($0)%" } ?? "Sin datos de batería")
    }
}

/// La bahía libre: sumar un robot.
private struct BahiaLibre: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.hundido.shadow(.inner(color: .black.opacity(0.9), radius: 6, y: 3)))
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay { Mas(tamano: 72) }
                .padding([.horizontal, .top], 12)
            VStack(alignment: .leading, spacing: 10) {
                Grabado("Bahía libre")
                Text("SUMAR UN ROBOT").font(Tipos.marca(24, .black)).tracking(-0.6).foregroundStyle(Color.papel)
            }
            .padding(20)
        }
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color(hex: 0x3A3632), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        .accessibilityElement(children: .combine)
    }
}

/// El "+" naranja inflado.
struct Mas: View {
    var tamano: CGFloat = 56
    var body: some View {
        Image(systemName: "plus").font(.system(size: tamano * 0.45, weight: .bold)).foregroundStyle(Color.tinta)
            .frame(width: tamano, height: tamano)
            .background(Circle().fill(LinearGradient(colors: [Color.brasa, Color(hex: 0xF2541A)], startPoint: .top, endPoint: .bottom)))
            .background(Circle().fill(Color(hex: 0x9A3209)).offset(y: 5))
            .shadow(color: .black.opacity(0.6), radius: 10, y: 12)
    }
}

/// Cómo sumar un robot: escanear su QR, o probar uno en el celu.
private struct SumarRobot: View {
    @Binding var ruta: [Ruta]
    let cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Grabado("Bahía libre", color: .brasa)
            Titular("Sumar un robot", tamano: 36)
            VStack(alignment: .leading, spacing: 12) {
                paso(1, "Prendelo: muestra un QR.")
                paso(2, "Escanealo.")
                paso(3, "Listo.")
            }
            Button { cerrar(); ruta.append(.escanear) } label: { Label("Escanear", systemImage: "qrcode.viewfinder") }
                .tecla(.naranja, ancha: true)
            HStack(spacing: 12) {
                Button { cerrar(); ruta.append(.robot(ID_DEMO)) } label: { Text("Probar Unidad") }.tecla(ancha: true)
                Button { cerrar(); ruta.append(.robot(ID_DEMO_BROCHE)) } label: { Text("Probar Broche") }.tecla(ancha: true)
            }
            Spacer()
        }
        .padding(24)
        .background(FondoConsola())
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.fondo)
    }

    private func paso(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)").font(Tipos.marca(14, .black)).foregroundStyle(Color.brasa)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9).fill(Color.hundido))
            Text(t).font(Tipos.marca(15, .semibold)).foregroundStyle(Color.hueso)
        }
    }
}
