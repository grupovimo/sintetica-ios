import SwiftUI

/// Los módulos: cada uno se abre en su pantalla (header + atrás) y se guarda solo.
enum Modulo: String, CaseIterable, Identifiable, Hashable {
    case listas, recordatorios, agenda, habitos, dia, jugar
    case cara, imagenes, modos, caracter, habla, voz, memoria, integraciones, reflejos
    case amigos, cuidado, avisos
    case ajustes
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .listas: "Listas"
        case .recordatorios: "Recordatorios"
        case .agenda: "Agenda"
        case .habitos: "Hábitos"
        case .dia: "Su día"
        case .jugar: "Jugar"
        case .cara: "Su cara"
        case .imagenes: "Imágenes"
        case .modos: "Su pantalla"
        case .caracter: "Carácter"
        case .habla: "Habla"
        case .voz: "Voz"
        case .memoria: "Memoria"
        case .integraciones: "Tu IA"
        case .reflejos: "Reflejos"
        case .amigos: "Amigos"
        case .cuidado: "Cuidado"
        case .avisos: "Avisos"
        case .ajustes: "La S1"
        }
    }

    var icono: Icono {
        switch self {
        case .listas: .lista
        case .recordatorios: .recordar
        case .agenda: .sistema("calendar")
        case .habitos: .check
        case .dia: .hoy
        case .jugar: .sistema("dice")
        case .cara: .sistema("face.smiling")
        case .imagenes: .sistema("photo")
        case .modos: .cubo
        case .caracter: .sistema("dial.medium")
        case .habla: .charla
        case .voz: .sistema("waveform")
        case .memoria: .sistema("book.closed")
        case .integraciones: .sistema("bolt")
        case .reflejos: .sistema("cable.connector")
        case .amigos: .sistema("person.2")
        case .cuidado: .sistema("pills")
        case .avisos: .sistema("bell")
        case .ajustes: .sistema("gearshape")
        }
    }

    /// Voz: solo si el modelo tiene micrófono o parlante.
    func bloqueado(_ m: ModeloProducto) -> Bool { self == .voz && !m.tiene(.microfono) && !m.tiene(.parlante) }
}

/// Lo que la S1 acaba de avisar sola (un recordatorio, el fin de un pomodoro,
/// tu IA). El ícono es su cara; el despertador es urgente: borde naranja y
/// dos acciones (APP.md, regla 5).
struct AvisoDelRobot: View {
    let aviso: ModeloRobot.Aviso
    let sesion: SesionS1
    /// El despertador sonando: posponer o apagar.
    var alarma: ((String) -> Void)? = nil
    let cerrar: () -> Void

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PantallaS1(sesion: sesion, tamano: .lista)
                Text(aviso.texto).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(3)
                Spacer(minLength: 0)
                if alarma == nil {
                    Button("OK", action: cerrar).tecla(chica: true)
                }
            }
            if let alarma {
                HStack(spacing: 8) {
                    Button { alarma("posponer") } label: { Text("Posponer") }.tecla(ancha: true)
                    Button { alarma("apagar") } label: { Text("Apagar") }.tecla(.naranja, ancha: true)
                }
            }
        }
        .padding(16)
        .background(forma.fill(Color.s1Superficie))
        .overlay(forma.strokeBorder(alarma == nil ? Color.clear : Color.s1Naranja, lineWidth: 2))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.warning, trigger: aviso)
        .accessibilityElement(children: .contain)
    }
}
