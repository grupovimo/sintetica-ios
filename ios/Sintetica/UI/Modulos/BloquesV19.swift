import CoreLocation
import SwiftUI

/// Su día → presencia: lo que aprendió la nube (cuándo salís, llegás y dormís)
/// con su seguridad, qué te dice al irte, y cómo se entera este iPhone.
@MainActor
struct BloquePresencia: View {
    let modelo: ModeloRobot
    @State private var horarios: Horarios?
    @State private var texto = ""
    private var presencia = PresenciaCelu.compartida

    init(modelo: ModeloRobot) { self.modelo = modelo }

    var body: some View {
        let c = modelo.config
        Bandeja {
            if modelo.esNube {
                HStack(spacing: 8) {
                    aprendido("Salís", "door.left.hand.open", horarios?.salis ?? "")
                    aprendido("Llegás", "house.fill", horarios?.llegas ?? "")
                    aprendido("Dormís", "moon.fill", horarios?.dormis ?? "")
                }
                HStack(spacing: 8) {
                    Grabado("Seguro", color: Color.tinta.opacity(0.66))
                    HStack(spacing: 4) {
                        ForEach(0 ..< 5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < (horarios?.segmentos ?? 0) ? Color.verde : Color(hex: 0x2C2925))
                                .frame(width: 22, height: 7)
                        }
                    }
                    Spacer()
                    Grabado("\(horarios?.dias ?? 0) d", color: Color.tinta.opacity(0.66))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Seguridad \(horarios?.segmentos ?? 0) de 5")
            }
            HStack(spacing: 8) {
                Llave(texto: "Al irte", prendida: c.presenciaPregunta) {
                    let t = modelo.config.presenciaTexto
                    let si = !modelo.config.presenciaPregunta
                    modelo.cambiar { $0.ponerPresencia(preguntar: si, texto: t) }
                }
                CampoVisor(rotulo: "Te dice", texto: $texto, ayuda: "¿Llevás las llaves?", claro: true) {
                    let t = texto
                    let si = modelo.config.presenciaPregunta
                    if cortarBytes(t.trimmingCharacters(in: .whitespaces), MAX_TEXTO_PRESENCIA) != modelo.config.presenciaTexto {
                        modelo.cambiar { $0.ponerPresencia(preguntar: si, texto: t) }
                    }
                }
                .onChange(of: texto) { _, v in let x = cortarBytes(v, MAX_TEXTO_PRESENCIA); if x != v { texto = x } }
                .opacity(c.presenciaPregunta ? 1 : 0.5)
                .disabled(!c.presenciaPregunta)
            }
            if modelo.esNube { esteCelu }
        }
        .task {
            texto = modelo.config.presenciaTexto
            guard modelo.esNube else { return }
            horarios = try? await Cuenta.compartida.api.horarios(modelo.id)
        }
    }

    private func aprendido(_ t: String, _ icono: String, _ h: String) -> some View {
        Visor(relleno: 10) {
            Image(systemName: icono).font(.system(size: 18, weight: .semibold)).foregroundStyle(h.isEmpty ? Color(hex: 0x5A524A) : Color.brasa)
            Grabado(t)
            Digitos(texto: h.isEmpty ? "--:--" : h, chicos: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Cómo se entera este iPhone de que llegás o te vas (opcional).
    @ViewBuilder private var esteCelu: some View {
        let _ = presencia.cambios
        let id = modelo.id
        Grabado("Este iPhone", color: Color.tinta.opacity(0.66))
        HStack(spacing: 8) {
            Llave(texto: "Bluetooth", prendida: presencia.porBluetooth(id), ancha: true) {
                presencia.ponerBluetooth(id, !presencia.porBluetooth(id))
            }
            .disabled(!presencia.conoceAlRobot(id))
            .opacity(presencia.conoceAlRobot(id) ? 1 : 0.5)
            Llave(texto: "Casa", prendida: presencia.porCasa(id), ancha: true) {
                presencia.ponerCasa(id, !presencia.porCasa(id))
            }
        }
        if presencia.porCasa(id) {
            HStack(spacing: 8) {
                Image(systemName: presencia.casaElegida ? "location.fill" : "location.slash").foregroundStyle(Color.tinta)
                Text(textoCasa).font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Button { presencia.elegirCasa() } label: { Text(presencia.casaElegida ? "Acá" : "Es acá") }.tecla(.negra, chica: true)
            }
        }
    }

    private var textoCasa: String {
        switch presencia.permisoUbicacion {
        case .denied, .restricted: "Sin permiso de ubicación"
        case .authorizedWhenInUse: "Falta \"Siempre\""
        default: presencia.casaElegida ? "Casa marcada" : "Marcá tu casa"
        }
    }
}

/// Spotify en Integraciones (solo si la nube lo tiene): conectarlo y lo que suena.
@MainActor
struct BloqueSpotify: View {
    @Environment(\.openURL) private var abrir
    @Environment(\.scenePhase) private var fase
    @State private var musica: Musica?
    @State private var oyente: UUID?

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        Group {
            if let m = musica, m.disponible {
                Bandeja {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.hundido)
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(hex: 0x3EE07A), Color(hex: 0x1DB954)], startPoint: .top, endPoint: .bottom)))
                            .background(RoundedRectangle(cornerRadius: 15).fill(Color(hex: 0x13863C)).offset(y: 4))
                        VStack(alignment: .leading, spacing: 4) {
                            Grabado("Spotify" + (m.nombre.isEmpty ? "" : " · \(m.nombre)"), color: Color.tinta.opacity(0.66))
                            if !m.conectada {
                                Text("QUE BAILE TU MÚSICA").font(Tipos.marca(15, .black)).foregroundStyle(Color.tinta).lineLimit(1).minimumScaleFactor(0.6)
                            } else if let s = m.suena, !s.titulo.isEmpty {
                                SuenaAhora(suena: s)
                            } else {
                                Text("CONECTADO").font(Tipos.marca(15, .black)).foregroundStyle(Color.tinta)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if m.conectada {
                        Button { Task { try? await api.desconectarSpotify(); await cargar() } } label: { Text("Desconectar") }.tecla(.negra, chica: true)
                    } else {
                        Button { conectar() } label: { Text("Conectar") }.tecla(.naranja, ancha: true)
                    }
                }
            }
        }
        .task { await cargar() }
        .onChange(of: fase) { _, f in if f == .active { Task { await cargar() } } }
        .onAppear {
            oyente = EnVivo.compartido.escuchar { e in
                guard e.tipo == "musica" else { return }
                if e.datos["conectada"] != nil { Task { await cargar() }; return }
                if let t = e.datos["titulo"] as? String {
                    musica?.suena = Suena(sonando: e.datos["sonando"] as? Bool ?? false, titulo: t, artista: e.datos["artista"] as? String ?? "")
                }
            }
        }
        .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
    }

    private func cargar() async { musica = try? await api.musica() }

    private func conectar() {
        Task {
            if let s = try? await api.enlaceSpotify(), let u = URL(string: s) { abrir(u) }
        }
    }
}

/// Lo que suena, con un ecualizador que se mueve.
struct SuenaAhora: View {
    let suena: Suena
    var claro = false

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !suena.sonando)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0 ..< 4, id: \.self) { i in
                        let f: Double = suena.sonando ? 0.25 + 0.75 * abs(sin(t * 4 + Double(i) * 1.3)) : 0.25
                        RoundedRectangle(cornerRadius: 2).fill(Color.led).frame(width: 4, height: 20 * f)
                    }
                }
                .frame(height: 20, alignment: .bottom)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(suena.titulo).font(Tipos.marca(14, .heavy)).foregroundStyle(claro ? Color.papel : Color.tinta).lineLimit(1)
                if !suena.artista.isEmpty { Text(suena.artista).font(Tipos.chico).foregroundStyle(Color.gris).lineLimit(1) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suena \(suena.titulo)")
    }
}
