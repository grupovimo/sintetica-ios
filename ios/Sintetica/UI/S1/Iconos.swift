import SwiftUI

/// Los íconos de la app (s1-pantalla.js, S1.IC): grilla de 24, trazo de 2,
/// puntas y uniones redondas. Los que el sistema no dibuja van con SF Symbols.
enum Icono: Hashable {
    case cubo, charla, hoy, mas, timer, lista, recordar, cobrar, check, mandar, menos, sumar, atras, adelante
    case sistema(String)
}

/// La forma de un ícono propio, en la grilla de 24.
struct FormaIcono: Shape {
    let icono: Icono

    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        let o = CGPoint(x: r.midX - 12 * k, y: r.midY - 12 * k)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
        func caja(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radio: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: o.x + x * k, y: o.y + y * k, width: w * k, height: h * k), cornerRadius: radio * k)
        }
        var c = Path()
        func linea(_ puntos: [CGPoint]) {
            guard let primero = puntos.first else { return }
            c.move(to: primero)
            for q in puntos.dropFirst() { c.addLine(to: q) }
        }
        switch icono {
        case .cubo:
            c.addPath(caja(3, 3, 18, 18, 4))
            linea([p(9.5, 10), p(9.5, 14)])
            linea([p(14.5, 10), p(14.5, 14)])
        case .charla:
            c.move(to: p(7, 4))
            c.addLine(to: p(17, 4))
            c.addArc(tangent1End: p(21, 4), tangent2End: p(21, 8), radius: 4 * k)
            c.addLine(to: p(21, 13))
            c.addArc(tangent1End: p(21, 17), tangent2End: p(17, 17), radius: 4 * k)
            c.addLine(to: p(12, 17))
            c.addLine(to: p(7, 21))
            c.addLine(to: p(7, 17))
            c.addArc(tangent1End: p(3, 17), tangent2End: p(3, 13), radius: 4 * k)
            c.addLine(to: p(3, 8))
            c.addArc(tangent1End: p(3, 4), tangent2End: p(7, 4), radius: 4 * k)
            c.closeSubpath()
        case .hoy:
            c.addEllipse(in: CGRect(x: o.x + 3 * k, y: o.y + 3 * k, width: 18 * k, height: 18 * k))
            linea([p(12, 7.5), p(12, 12), p(15, 14)])
        case .mas:
            c.addPath(caja(3, 3, 6, 6, 2))
            c.addPath(caja(15, 3, 6, 6, 2))
            c.addPath(caja(3, 15, 6, 6, 2))
            c.addPath(caja(15, 15, 6, 6, 2))
        case .timer:
            c.addEllipse(in: CGRect(x: o.x + 5 * k, y: o.y + 7 * k, width: 14 * k, height: 14 * k))
            linea([p(10, 3), p(14, 3)])
            linea([p(12, 14), p(12, 10.5)])
        case .lista:
            linea([p(9.5, 7), p(20, 7)])
            linea([p(9.5, 12), p(20, 12)])
            linea([p(9.5, 17), p(16, 17)])
            linea([p(4.5, 6), p(4.5, 8)])
            linea([p(4.5, 11), p(4.5, 13)])
            linea([p(4.5, 16), p(4.5, 18)])
        case .recordar:
            c.addPath(caja(3, 5, 18, 16, 4))
            linea([p(8, 3), p(8, 7)])
            linea([p(16, 3), p(16, 7)])
            linea([p(3, 10.5), p(21, 10.5)])
            linea([p(12, 14), p(12, 17)])
        case .cobrar:
            c.addPath(caja(3, 3, 6, 6, 2))
            c.addPath(caja(15, 3, 6, 6, 2))
            c.addPath(caja(3, 15, 6, 6, 2))
            linea([p(16, 15), p(16, 20)])
            linea([p(20, 15), p(20, 20)])
        case .check:
            linea([p(5, 12.5), p(9.5, 17), p(19, 7.5)])
        case .mandar:
            linea([p(12, 19), p(12, 5)])
            linea([p(6, 11), p(12, 5), p(18, 11)])
        case .menos:
            linea([p(6, 12), p(18, 12)])
        case .sumar:
            linea([p(12, 6), p(12, 18)])
            linea([p(6, 12), p(18, 12)])
        case .atras:
            linea([p(15, 5), p(8, 12), p(15, 19)])
        case .adelante:
            linea([p(9, 5), p(16, 12), p(9, 19)])
        case .sistema:
            break
        }
        return c
    }
}

/// Un ícono de 24 (o del tamaño que se pida), en el color de primer plano.
struct IconoS1: View {
    let icono: Icono
    var tamano: CGFloat = 24

    init(_ icono: Icono, tamano: CGFloat = 24) {
        self.icono = icono
        self.tamano = tamano
    }

    var body: some View {
        Group {
            if case let .sistema(nombre) = icono {
                Image(systemName: nombre).font(.system(size: tamano * 0.78, weight: .semibold))
            } else {
                FormaIcono(icono: icono)
                    .stroke(style: StrokeStyle(lineWidth: max(1.5, 2 * tamano / 24), lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: tamano, height: tamano)
        .accessibilityHidden(true)
    }
}
