import SwiftUI

/// El header de las tabs y de los detalles (S1 Header): a la izquierda el
/// título (con la flecha si vuelve) y el chip de estado debajo; a la derecha
/// su pantalla de 72 con la cara del momento. 72 de alto debajo de la barra
/// de estado; el contenido arranca 24 más abajo.
struct HeaderS1: View {
    let titulo: String
    var sesion: SesionS1?
    var atras: (() -> Void)? = nil
    /// Sin la de 72 cuando la pantalla ya muestra la de 160 (APP.md).
    var conPantalla = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let atras {
                        Button(action: atras) {
                            IconoS1(.atras).foregroundStyle(Color.s1Tinta)
                                .frame(width: 32, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, -8)
                        .accessibilityLabel("Atrás")
                    }
                    Text(titulo).font(S1Tipo.titulo).tracking(-0.56).foregroundStyle(Color.s1Tinta)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(height: 32)
                if let sesion { ChipEstado(estado: sesion.estado) }
            }
            Spacer(minLength: 0)
            if conPantalla, let sesion { PantallaS1(sesion: sesion) }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .background(Color.s1Fondo)
    }
}

/// Las cuatro tabs: Inicio (con su nombre), Charla, Hoy y Más.
enum PestanaS1: String, CaseIterable, Identifiable {
    case inicio, charla, hoy, mas
    var id: String { rawValue }

    var icono: Icono {
        switch self {
        case .inicio: .cubo
        case .charla: .charla
        case .hoy: .hoy
        case .mas: .mas
        }
    }
}

/// La tab bar (S1 Tabbar): 64 + la zona del home, con la píldora en tinta
/// invertida detrás del ícono elegido.
struct TabBarS1: View {
    @Binding var actual: PestanaS1
    let nombre: String

    private func titulo(_ p: PestanaS1) -> String {
        switch p {
        case .inicio: nombre
        case .charla: "Charla"
        case .hoy: "Hoy"
        case .mas: "Más"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PestanaS1.allCases) { p in
                let si = p == actual
                Button { actual = p } label: {
                    VStack(spacing: 2) {
                        IconoS1(p.icono)
                            .foregroundStyle(si ? Color.s1InvTexto : Color.s1Tinta2)
                            .frame(width: 56, height: 32)
                            .background(Capsule().fill(si ? Color.s1Inv : Color.clear))
                        Text(titulo(p)).font(si ? S1Tipo.captionFuerte : S1Tipo.caption)
                            .foregroundStyle(si ? Color.s1Tinta : Color.s1Tinta2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(titulo(p))
                .accessibilityAddTraits(si ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .background(Color.s1Fondo.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
        .sensoryFeedback(.selection, trigger: actual)
    }
}
