import SwiftUI

/// 13 · Timer: el anillo en su pantalla de 160, los minutos (1 · 5 · 10 · 15 ·
/// 25), el nombre, los recientes y, andando, +1 min / Pausa / Cancelar.
@MainActor
struct TimerVista: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var minutos = 10
    @State private var nombre = ""

    private static let opciones = [1, 5, 10, 15, 25]
    private var timer: TimerS1 { sesion.timer }

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Timer", sesion: sesion, atras: { ir(.cerrarModulo) }, conPantalla: false)
            CuerpoConBoton {
                PantallaGrande {
                    if timer.t != nil {
                        PantallaTimer(restante: timer.restante, total: timer.total, etiqueta: timer.etiqueta, pausado: timer.pausado, listo: timer.listo)
                    } else {
                        PantallaTimer(restante: minutos * 60, total: minutos * 60, etiqueta: nombre)
                    }
                }
                if timer.activo {
                    andando
                } else {
                    elegir
                }
                if !sesion.modelo.conectado && sesion.charla == nil {
                    EstadoSinConexion(nombre: sesion.nombre) { Task { await sesion.reintentar() } }
                }
            } boton: {
                if timer.activo {
                    if timer.pausado {
                        BotonS1("Seguir") { timer.seguir() }
                    } else {
                        BotonS1("Cancelar", naranja: false) { timer.cancelar() }
                    }
                } else {
                    BotonS1("Empezar") { timer.empezar(minutos: minutos, etiqueta: nombre) }
                        .disabled(sesion.pensando)
                }
            }
        }
        .background(FondoConsola())
        .onAppear {
            if let r = timer.recientes.first, nombre.isEmpty, timer.t == nil { minutos = Self.opciones.contains(r.minutos) ? r.minutos : minutos }
        }
    }

    private var elegir: some View {
        VStack(alignment: .leading, spacing: 0) {
            Seccion("Minutos")
            Segmentado(opciones: Self.opciones.map { (clave: String($0), nombre: String($0)) }, elegida: String(minutos)) { k in
                minutos = Int(k) ?? 10
            }
            CampoS1(ayuda: "¿Para qué? La pasta, el té…", texto: $nombre).padding(.top, 12)
                .onChange(of: nombre) { _, v in if v.count > 24 { nombre = String(v.prefix(24)) } }
            Seccion("Recientes")
            VStack(spacing: 0) {
                ForEach(timer.recientes) { r in
                    Button { timer.empezar(minutos: r.minutos, etiqueta: r.etiqueta) } label: {
                        FilaS1(titulo: r.etiqueta, valor: "\(r.minutos) min", flecha: true) { IconoEnCirculo(icono: .timer) }
                    }
                    .buttonStyle(.plain)
                    .disabled(sesion.pensando)
                }
            }
        }
    }

    private var andando: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(timer.listo ? "¡Listo!" : timer.texto).font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.s1Tinta).frame(maxWidth: .infinity).padding(.top, 16)
                .contentTransition(.numericText())
            if !timer.etiqueta.isEmpty {
                Text(timer.etiqueta).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta2).frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                BotonS1("+1 min", naranja: false) { timer.sumarMinuto() }
                if timer.pausado {
                    BotonS1("Cancelar", naranja: false) { timer.cancelar() }
                } else {
                    BotonS1("Pausa", naranja: false) { timer.pausar() }
                }
            }
            .padding(.top, 24)
        }
    }
}
