import SwiftUI

/// El Laboratorio: lo avanzado, como módulos de rack (Expresiones,
/// Comportamientos y Reglas). Como web/src/routes/robots/[id]/+layout.svelte.
@MainActor
struct LaboratorioVista: View {
    let modelo: ModeloRobot
    @Environment(\.dismiss) private var cerrar
    @State private var rack: Rack
    @State private var cerca = false

    init(modelo: ModeloRobot, rack: Rack = .expresiones) {
        self.modelo = modelo
        _rack = State(initialValue: rack)
    }

    enum Rack: String, CaseIterable, Identifiable {
        case expresiones, comportamientos, reglas, vida, dibujos, animaciones, firmware, historial
        var id: String { rawValue }
        var nombre: String {
            switch self {
            case .expresiones: "Expresiones"
            case .comportamientos: "Comportamientos"
            case .reglas: "Reglas"
            case .vida: "Vida"
            case .dibujos: "Dibujos"
            case .animaciones: "Animaciones"
            case .firmware: "Firmware"
            case .historial: "Historial"
            }
        }

        var icono: String {
            switch self {
            case .expresiones: "eye"
            case .comportamientos: "flag.fill"
            case .reglas: "arrow.triangle.branch"
            case .vida: "waveform.path.ecg"
            case .dibujos: "pencil.and.outline"
            case .animaciones: "play.rectangle.fill"
            case .firmware: "arrow.down.circle.fill"
            case .historial: "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { cerrar() } label: { Label("Consola", systemImage: "chevron.left") }.tecla(.negra, chica: true)
                    Spacer()
                    Grabado("Laboratorio · \(modelo.nombre)", color: .brasa)
                }
                .padding(.top, 8)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Rack.allCases) { r in
                        Button { rack = r } label: {
                            VStack(spacing: 8) {
                                Image(systemName: r.icono).font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(rack == r ? Color.brasa : Color.tinta)
                                Text(r.nombre.uppercased()).font(Tipos.angosta(10, .black)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundStyle(rack == r ? Color.papel : Color.tinta)
                            .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(EstiloTeclaModulo(elegido: rack == r))
                        .accessibilityAddTraits(rack == r ? [.isSelected] : [])
                    }
                }
                switch rack {
                case .expresiones: LabExpresiones(modelo: modelo)
                case .comportamientos: LabComportamientos(modelo: modelo)
                case .reglas: LabReglas(modelo: modelo)
                case .vida: LabVida(modelo: modelo)
                case .dibujos: LabDibujos(modelo: modelo)
                case .animaciones: LabAnimaciones(modelo: modelo)
                case .firmware: LabFirmware(modelo: modelo) { cerca = true }
                case .historial: LabHistorial(modelo: modelo)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FondoConsola())
        .sheet(isPresented: $cerca) { CercaVista(modelo: modelo) }
    }
}

/// El nombre de lo que se edita y los botones de siempre.
struct BarraLab: View {
    @Binding var nombre: String
    let fijo: Bool
    let enRobot: (() -> Void)?
    let original: (() -> Void)?
    let textoOriginal: String
    let guardar: () -> Void
    let textoGuardar: String
    let puedeGuardar: Bool

    var body: some View {
        VStack(spacing: 10) {
            Visor(relleno: 10) {
                Grabado("Nombre")
                TextField("", text: $nombre).font(Tipos.marca(20, .black)).foregroundStyle(Color.brasa)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(fijo)
            }
            Flujo(espacio: 8, renglon: 4) {
                if let enRobot { Button(action: enRobot) { Label("En el robot", systemImage: "play.fill") }.tecla(.negra, chica: true) }
                if let original { Button(action: original) { Text(textoOriginal) }.tecla(.negra, chica: true) }
                Button(action: guardar) { Text(textoGuardar) }.tecla(.naranja, chica: true).disabled(!puedeGuardar)
            }
        }
    }
}

/// Una fila de chips (una tecla chica por opción).
struct Chips: View {
    let opciones: [String]
    let elegida: String?
    var texto: (String) -> String = { $0 }
    let alElegir: (String) -> Void

    var body: some View {
        Flujo(espacio: 8, renglon: 4) {
            ForEach(opciones, id: \.self) { o in
                Button { alElegir(o) } label: { Text(texto(o)) }.tecla(chica: true, hundida: elegida == o)
            }
        }
    }
}
