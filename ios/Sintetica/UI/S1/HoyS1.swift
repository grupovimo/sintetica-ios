import SwiftUI

/// 10 · Hoy: lo de ahora, lo de más tarde, cosas de un toque y lo de mañana.
/// Abajo, fijo, "Nuevo" (un recordatorio).
@MainActor
struct HoyS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void

    private static let deUnToque = ["Timer de 10", "Anotá leche", "¿Llueve mañana?", "Buenas noches"]

    var body: some View {
        let modelo = sesion.modelo
        VStack(spacing: 0) {
            HeaderS1(titulo: "Hoy", sesion: sesion)
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch modelo.fase {
                        case .conectando: EstadoCargando(renglones: 3)
                        case .error: EstadoSinConexion(nombre: sesion.nombre) { Task { await sesion.reintentar() } }
                        case .lista: contenido
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, AIRE_BOTON_FIJO)
                }
                .scrollIndicators(.hidden)
                if modelo.fase == .lista {
                    BotonFijo {
                        BotonS1("Nuevo", accion: nuevo)
                            .disabled(modelo.config.recordatorios.count >= MAX_RECORDATORIOS)
                    }
                }
            }
        }
        .background(FondoConsola())
    }

    @ViewBuilder private var contenido: some View {
        let c = sesion.modelo.config
        let hoy = ProximosS1.de(c, limite: 20)
        let manana = ProximosS1.de(c, limite: 5, ahora: Date().addingTimeInterval(86400), soloDesdeAhora: false)
        Seccion("Ahora", arriba: 0)
        if let primero = hoy.first {
            ahora(primero)
        } else {
            EstadoVacio(texto: "Nada por hoy.", expresion: sesion.estado == .durmiendo ? "dormido" : "contento")
        }
        if hoy.count > 1 {
            Seccion("Más tarde")
            filas(Array(hoy.dropFirst()))
        }
        Seccion("De un toque")
        Flujo(espacio: 8, renglon: 8) {
            ForEach(Self.deUnToque, id: \.self) { t in
                ChipS1(t) { ir(.charlar(t)) }
            }
        }
        .disabled(sesion.charla == nil && !sesion.modelo.conectado)
        if !manana.isEmpty {
            Seccion("Mañana")
            filas(manana)
        }
    }

    /// Lo primero que viene, grande.
    private func ahora(_ p: ProximosS1) -> some View {
        Button { ir(.modulo(p.modulo)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.titulo).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).lineLimit(2)
                    Text(p.hora).font(S1Tipo.dato).foregroundStyle(Color.s1Tinta)
                }
                Spacer(minLength: 8)
                IconoS1(p.icono).foregroundStyle(Color.s1Tinta)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.s1Fondo))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func filas(_ l: [ProximosS1]) -> some View {
        VStack(spacing: 0) {
            ForEach(l) { p in
                Button { ir(.modulo(p.modulo)) } label: {
                    FilaS1(titulo: p.titulo, detalle: p.detalle, valor: p.hora) { IconoEnCirculo(icono: p.icono) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nuevo() {
        sesion.modelo.cambiar { $0.recordatorios = $0.recordatorios + [Recordatorio.nuevo()] }
        ir(.modulo(.recordatorios))
    }
}
