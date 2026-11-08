import SwiftUI

/// Vida: lo que siente ahora (vúmetros de los 7 estados, pedidos cada 2 s
/// mientras está abierta), su diario (lo que recuerda) y la mudanza. Como
/// web/src/routes/robots/[id]/vida/+page.svelte.
@MainActor
struct LabVida: View {
    let modelo: ModeloRobot
    @State private var memoria: Memoria?
    @State private var mudanzaPendiente = false
    @State private var otros: [RobotNube] = []
    @State private var desde = ""
    @State private var aviso = ""
    @State private var error = ""
    @State private var superposicion = false
    @State private var resumen: ResumenDia?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ahora
            if modelo.esNube {
                if let r = resumen { suDia(r) }
                diario
                mudanza
            }
        }
        .task {
            // El estado en vivo: cada 2 s mientras esté abierta (y la memoria cada minuto).
            var vuelta = 0
            while !Task.isCancelled {
                await modelo.pedirVida()
                if modelo.esNube, vuelta % 30 == 0 {
                    await cargarMemoria()
                    resumen = try? await api.resumen(modelo.id)
                }
                vuelta += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            guard modelo.esNube, let l = try? await api.robots() else { return }
            otros = l.filter { $0.id != modelo.id }
        }
    }

    private func cargarMemoria() async {
        do {
            let r = try await api.memoria(modelo.id)
            memoria = r.memoria
            mudanzaPendiente = r.mudanzaPendiente
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Ahora

    private var ahora: some View {
        let vida = modelo.vida
        let vieja = Date().timeIntervalSince(modelo.vidaEn) > 8
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Led(estado: vida != nil && !vieja ? .verde : .apagado)
                Grabado("Ahora")
                Spacer()
                Llave(texto: "En su pantalla", prendida: superposicion) {
                    superposicion.toggle()
                    let s = superposicion
                    Task { await modelo.pedirVida(superposicion: s) }
                }
                .disabled(!modelo.conectado)
            }
            Text(haciendo(vida).uppercased()).font(Tipos.marca(32, .black)).tracking(-1)
                .foregroundStyle(vida == nil ? Color(hex: 0x5A524A) : Color.brasa).lineLimit(2).minimumScaleFactor(0.5)
            if let vida {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(VARIABLES_ESTADO, id: \.self) { v in Vumetro(nombre: NOMBRES_ESTADO[v] ?? v, valor: vida.estado[v] ?? 0, estres: v == "estres") }
                }
                .padding(.horizontal, 10).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.hundido.shadow(.inner(color: .black.opacity(0.8), radius: 5, y: 3))))
            }
        }
        .padding(20)
        .chapa()
        .animation(.easeOut(duration: 0.3), value: vida)
    }

    private func haciendo(_ v: VidaEnVivo?) -> String {
        if !modelo.conectado { return "Desconectado" }
        guard let v else { return "Escuchando…" }
        if v.dormido { return v.sonando ? "Soñando" : "Durmiendo" }
        return v.comportamiento.isEmpty ? "Tranqui" : v.comportamiento.replacingOccurrences(of: "-", with: " ")
    }

    // MARK: Su día (lo de hoy, contado)

    private static let suenos: [String: String] = ["corazon": "♥", "estrella": "★", "nota": "♪", "oveja": "🐑", "pesadilla": "⚡"]
    private static let caraAnimo: [String: String] = ["bien": "😀", "medio": "😐", "mal": "😞"]

    private func suDia(_ r: ResumenDia) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Grabado("Su día")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Visor(relleno: 12) {
                    Grabado("Juegos")
                    Digitos(texto: r.ganados > 0 ? "\(r.juegos) · \(r.ganados)" : "\(r.juegos)", chicos: true)
                }
                Visor(relleno: 12) {
                    Grabado("Soñó")
                    if r.sonoCon.isEmpty {
                        Digitos(texto: "\(r.suenos)", chicos: true)
                    } else {
                        Text(r.sonoCon.map { Self.suenos[$0] ?? "·" }.joined(separator: " ")).font(.system(size: 20)).foregroundStyle(Color.brasa)
                    }
                }
                Visor(relleno: 12) {
                    Grabado("Ánimo")
                    Text(r.animo.flatMap { Self.caraAnimo[$0] } ?? "—").font(.system(size: 24)).foregroundStyle(Color.gris)
                }
                Visor(relleno: 12) {
                    Grabado("Te esperó")
                    Digitos(texto: r.espero.isEmpty ? "—" : r.espero, chicos: true)
                }
            }
        }
        .padding(20)
        .chapa()
    }

    // MARK: Diario

    private var diario: some View {
        PlacaNaranja {
            Grabado("Diario", color: Color.tinta.opacity(0.66))
            if let m = memoria {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    contador("Días juntos", m.dias)
                    contador("Racha", m.racha)
                    contador("Caricias", m.caricias)
                    contador("Toques", m.toques)
                }
                if !m.hitos.isEmpty {
                    Flujo(espacio: 8, renglon: 8) {
                        ForEach(m.hitos, id: \.self) { h in Medalla(texto: NOMBRES_HITO[h] ?? h) }
                    }
                }
                Bandeja(relleno: 14, espacio: 10) {
                    Grabado(m.horaPreferida.map { "Te espera a las \($0):00" } ?? "Cuándo aparecés", color: Color.tinta.opacity(0.66))
                    BarrasHoras(horas: m.horas, pico: m.horaPreferida)
                }
                if !m.mejoresGustos.isEmpty {
                    Flujo(espacio: 8, renglon: 8) {
                        Grabado("Le gusta", color: Color.tinta.opacity(0.66))
                        ForEach(m.mejoresGustos, id: \.self) { g in Chip(texto: "♥ \(NOMBRES_EVENTO[g] ?? g)") }
                    }
                }
                let cambiados = RASGOS.filter { (m.deriva[$0] ?? 0) != 0 }
                if !cambiados.isEmpty {
                    Flujo(espacio: 8, renglon: 8) {
                        Grabado("Lo cambiaste", color: Color.tinta.opacity(0.66))
                        ForEach(cambiados, id: \.self) { r in Chip(texto: "\((m.deriva[r] ?? 0) > 0 ? "▲" : "▼") \(NOMBRES_RASGO[r] ?? r)") }
                    }
                }
            } else {
                Text("Todavía sin recuerdos.").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8))
            }
        }
    }

    private func contador(_ t: String, _ n: Int) -> some View {
        Visor(relleno: 12) {
            Grabado(t)
            Digitos(texto: "\(n)")
        }
    }

    // MARK: Mudanza

    private var mudanza: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grabado("Mudanza" + (mudanzaPendiente ? " · en camino" : ""))
            HStack(spacing: 10) {
                Menu {
                    ForEach(otros) { o in Button(o.apodo.isEmpty ? (o.estado?.nombre ?? o.id) : o.apodo) { desde = o.id } }
                } label: {
                    HStack {
                        Text(nombreDe(desde)).font(Tipos.marca(14, .bold)).foregroundStyle(Color.papel).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.gris)
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.hundido))
                }
                .disabled(otros.isEmpty)
                Button { mudar() } label: { Text("Mudar") }.tecla(.naranja, chica: true).disabled(desde.isEmpty)
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso) }
            if !error.isEmpty { AvisoConsola(texto: error, error: true) }
        }
        .padding(20)
        .chapa()
    }

    private func nombreDe(_ id: String) -> String {
        if id.isEmpty { return otros.isEmpty ? "No hay otro robot" : "Traer la memoria de…" }
        guard let o = otros.first(where: { $0.id == id }) else { return id }
        return o.apodo.isEmpty ? (o.estado?.nombre ?? o.id) : o.apodo
    }

    private func mudar() {
        aviso = ""
        error = ""
        let d = desde
        Task {
            do {
                try await api.mudar(modelo.id, desde: d)
                aviso = "Le llega al conectarse."
                mudanzaPendiente = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Un vúmetro de 12 luces.
private struct Vumetro: View {
    let nombre: String
    let valor: Double
    let estres: Bool

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                ForEach(0 ..< 12, id: \.self) { j in
                    let k = 11 - j
                    let on = valor * 12 > Double(k)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(on ? color(k) : Color(hex: 0x2A2622))
                        .frame(height: 8)
                        .shadow(color: on ? color(k) : .clear, radius: 3)
                }
            }
            .frame(maxWidth: 24)
            Text(nombre.uppercased()).font(Tipos.angosta(8, .heavy)).foregroundStyle(Color.gris).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
        .accessibilityValue("\(Int((valor * 100).rounded()))")
    }

    private func color(_ k: Int) -> Color { estres ? Color(hex: 0xFF3B3B) : k >= 9 ? Color.ambar : Color.led }
}

/// Las 24 barras de "cuándo aparecés".
private struct BarrasHoras: View {
    let horas: [Int]
    let pico: Int?

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(horas.enumerated()), id: \.offset) { h, v in
                    let alto: CGFloat = CGFloat(max(4, min(100, v * 8))) / 100 * 80
                    RoundedRectangle(cornerRadius: 2)
                        .fill(h == pico ? Color.tinta : Color.tinta.opacity(0.55))
                        .frame(height: alto)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80, alignment: .bottom)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text("\(h)").font(Tipos.marca(10, .heavy)).foregroundStyle(Color.tinta.opacity(0.66))
                    if h < 24 { Spacer() }
                }
            }
        }
        .accessibilityLabel("A qué hora aparecés")
    }
}

struct Medalla: View {
    let texto: String
    var body: some View {
        Label(texto, systemImage: "star.fill").font(Tipos.marca(11, .heavy)).foregroundStyle(Color.ambar)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tinta))
    }
}

struct Chip: View {
    let texto: String
    var body: some View {
        Text(texto).font(Tipos.marca(11, .heavy)).foregroundStyle(Color.papel)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tinta))
    }
}
