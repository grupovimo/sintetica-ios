import SwiftUI

/// 34 · Más: el hub de la 4.ª tab. Arriba ella (lleva a La S1); abajo, cada
/// módulo como tecla de 88, en grupos.
@MainActor
struct MasS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void

    private struct Tecla: Identifiable {
        let id: String
        let nombre: String
        let icono: Icono
        let destino: IrA
    }

    private static func de(_ m: Modulo) -> Tecla { Tecla(id: m.rawValue, nombre: m.nombre, icono: m.icono, destino: .modulo(m)) }

    private static let todosLosDias: [Tecla] = [Modulo.listas, .recordatorios, .agenda, .habitos, .dia, .jugar].map(MasS1.de)
    private static let ella: [Tecla] = [MasS1.de(.cara), MasS1.de(.imagenes), MasS1.de(.modos), MasS1.de(.caracter), MasS1.de(.habla), MasS1.de(.voz),
                                 MasS1.de(.memoria), Tecla(id: "diario", nombre: "El diario", icono: .sistema("sparkles"), destino: .laboratorio(.vida)),
                                 MasS1.de(.integraciones), MasS1.de(.reflejos)]
    private static let suGente: [Tecla] = [Modulo.amigos, .cuidado, .avisos].map(MasS1.de)
    private static let vos: [Tecla] = [
        MasS1.de(.ajustes),
        Tecla(id: "mis", nombre: "Mis S1", icono: .cubo, destino: .misS1),
        Tecla(id: "cuenta", nombre: "Cuenta", icono: .sistema("person"), destino: .cuenta),
        Tecla(id: "lab", nombre: "Laboratorio", icono: .sistema("flask"), destino: .laboratorio(.expresiones)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HeaderS1(titulo: "Más", sesion: sesion, conPantalla: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tarjeta(sesion)
                    grupo("Todos los días", Self.todosLosDias)
                    grupo("Ella", Self.ella)
                    grupo("Su gente", Self.suGente)
                    grupo("Vos", Self.vos)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(FondoConsola())
    }

    /// La tarjeta de ella: su pantalla, su nombre y cómo está.
    private func tarjeta(_ s: SesionS1) -> some View {
        Button { ir(.modulo(.ajustes)) } label: {
            HStack(spacing: 16) {
                PantallaS1(sesion: s)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.nombre).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.s1Tinta).lineLimit(1).minimumScaleFactor(0.7)
                    ChipEstado(estado: s.estado)
                }
                Spacer(minLength: 0)
                IconoS1(.adelante, tamano: 20).foregroundStyle(Color.s1Tinta2)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.s1Superficie))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("La S1")
    }

    private func grupo(_ titulo: String, _ teclas: [Tecla]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Seccion(titulo)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(teclas) { t in
                    TeclaAtajo(icono: t.icono, nombre: t.nombre, alto: 88) { ir(t.destino) }
                }
            }
        }
    }
}
