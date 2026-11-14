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

/// 22 · Mis S1: cada una con su pantalla de 72, dónde está y cómo está;
/// abajo, fija, "Sumar otra S1". Tocar una la elige y vuelve al Inicio.
@MainActor
struct MisS1: View {
    @Binding var ruta: [Ruta]
    var esRaiz = false
    private var cuenta = Cuenta.compartida
    private var vinculados = Vinculados.compartidos
    private var enVivo = EnVivo.compartido
    @State private var nube: [RobotNube] = []
    @State private var configs: [String: String] = [:]
    @State private var cargando = true
    @State private var error = ""
    @State private var sumando = false
    @State private var oyente: UUID?
    @Environment(\.dismiss) private var cerrar

    init(ruta: Binding<[Ruta]>, esRaiz: Bool = false) {
        _ruta = ruta
        self.esRaiz = esRaiz
    }

    private var robots: [RobotDock] {
        var l: [RobotDock] = nube.map { (r: RobotNube) -> RobotDock in
            RobotDock(id: r.id, nombre: nombreDe(r), perfil: r.perfil, virtual: r.virtual, conectado: r.conectado,
                      ultimaConexion: r.ultimaConexion, estado: r.estado, soloCerca: false, config: configs[r.id])
        }
        for v in vinculados.todos where !l.contains(where: { $0.id == v.id }) {
            l.append(RobotDock(id: v.id, nombre: v.nombre == "bicho" ? "Tu S1" : v.nombre, perfil: "", virtual: false, conectado: false,
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
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HeaderS1(titulo: "Mis S1", atras: accionAtras, conPantalla: false)
                if esRaiz {
                    Button { ruta.append(.cuenta) } label: {
                        IconoS1(.sistema(cuenta.activa ? "person.crop.circle.fill" : "person.crop.circle")).foregroundStyle(Color.s1Tinta)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .accessibilityLabel(cuenta.activa ? "Cuenta" : "Entrar")
                }
            }
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.bottom, 16) }
                        if cargando && robots.isEmpty {
                            EstadoCargando(renglones: 3)
                        } else if robots.isEmpty {
                            EstadoVacio(texto: "Todavía ninguna.", expresion: "dormido")
                        } else {
                            ForEach(robots) { r in
                                Button { elegir(r.id) } label: { FilaRobot(robot: r) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, AIRE_BOTON_FIJO)
                }
                .refreshable { await cargar() }
                BotonFijo { BotonS1("Sumar otra S1") { sumando = true } }
            }
        }
        .background(FondoConsola())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: cuenta.activa) { await cargar() }
        .onAppear { oyente = enVivo.escuchar { e in recibir(e) } }
        .onDisappear { if let o = oyente { enVivo.dejar(o) } }
        .sheet(isPresented: $sumando) { SumarRobot(ruta: $ruta, cerrar: { sumando = false }) }
    }

    private var accionAtras: (() -> Void)? {
        if esRaiz { return nil }
        return { volver() }
    }

    private func volver() {
        if !Navegacion.volver(&ruta) { cerrar() }
    }

    private func elegir(_ id: String) {
        Navegacion.abrir(id, &ruta)
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

/// Un renglón de Mis S1: su pantalla de 72, nombre, detalle y estado.
private struct FilaRobot: View {
    let robot: RobotDock

    private var estado: EstadoS1 {
        if robot.soloCerca { return .despierta }
        if !robot.conectado { return .sinConexion }
        return robot.estado?.dormido == true ? .durmiendo : .despierta
    }

    private var detalle: String {
        if robot.soloCerca { return "Por Bluetooth" }
        var d = robot.conectado ? animoDe(robot.estado, conectado: true) : "Visto \(hace(robot.ultimaConexion))"
        if let b = robot.estado?.bateria { d += " · \(b)%" }
        return d
    }

    var body: some View {
        HStack(spacing: 16) {
            MarcoPantalla(tamano: .header) {
                if estado == .sinConexion {
                    PantallaSinWifi(tamano: 20)
                } else {
                    CaraDibujada(expresion: estado == .durmiendo ? "dormido" : nombreDibujable(robot.estado?.expresion ?? "neutral"),
                                 config: robot.config, pantalla: robot.pantalla, fps: 8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(robot.nombre).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta).lineLimit(1)
                Text(detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(estado.led).frame(width: 8, height: 8)
                    Text(estado.texto).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta)
                }
            }
            Spacer(minLength: 0)
            IconoS1(.adelante, tamano: 20).foregroundStyle(Color.s1Tinta2)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

/// El "+" naranja inflado.
struct Mas: View {
    var tamano: CGFloat = 56
    var body: some View {
        Image(systemName: "plus").font(.system(size: tamano * 0.45, weight: .bold)).foregroundStyle(Color.s1TintaFija)
            .frame(width: tamano, height: tamano)
            .background(Circle().fill(LinearGradient(colors: [Color.s1NaranjaBrillo, Color.s1Naranja], startPoint: .top, endPoint: .bottom)))
            .background(Circle().fill(Color.s1NaranjaCanto).offset(y: 4))
    }
}

/// Cómo sumar una S1: escanear su QR, o probar una en el celu.
@MainActor
private struct SumarRobot: View {
    @Binding var ruta: [Ruta]
    let cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Titular("Sumar una S1")
            VStack(alignment: .leading, spacing: 12) {
                paso(1, "Prendelo: muestra un QR.")
                paso(2, "Escanealo.")
                paso(3, "Listo.")
            }
            Button { cerrar(); ruta.append(.escanear) } label: { Label("Escanear", systemImage: "qrcode.viewfinder") }
                .tecla(.naranja, ancha: true)
            HStack(spacing: 12) {
                Button { cerrar(); Navegacion.abrir(ID_DEMO, &ruta) } label: { Text("Probar Unidad") }.tecla(ancha: true)
                Button { cerrar(); Navegacion.abrir(ID_DEMO_BROCHE, &ruta) } label: { Text("Probar Broche") }.tecla(ancha: true)
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
            Text("\(n)").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                .frame(width: 32, height: 32).background(Circle().fill(Color.s1Superficie))
            Text(t).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta)
        }
    }
}
