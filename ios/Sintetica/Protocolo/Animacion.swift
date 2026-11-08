import Foundation

/// Una imagen animada ("sani", ver firmware/nucleo/qoi.h): la cabecera, la tabla
/// de cuadros y cada cuadro en QOI, en el mismo archivo. Igual que
/// codificarAnimacion de sim/web/qoi.js.
enum Animacion {
    static let maxCuadros = 64

    struct Cuadro {
        var qoi: [UInt8]
        var ms: Int
    }

    static func codificar(_ cuadros: [Cuadro], ancho: Int, alto: Int) -> [UInt8] {
        let tabla = 10 + 10 * cuadros.count
        var salida = [UInt8](repeating: 0, count: tabla + cuadros.reduce(0) { $0 + $1.qoi.count })
        func u16(_ p: Int, _ v: Int) { salida[p] = UInt8(v & 255); salida[p + 1] = UInt8((v >> 8) & 255) }
        func u32(_ p: Int, _ v: Int) { for k in 0 ..< 4 { salida[p + k] = UInt8((v >> (8 * k)) & 255) } }
        salida.replaceSubrange(0 ..< 6, with: [0x73, 0x61, 0x6E, 0x69, 1, UInt8(cuadros.count)])
        u16(6, ancho)
        u16(8, alto)
        var off = tabla
        for (i, c) in cuadros.enumerated() {
            u16(10 + 10 * i, min(65535, max(20, c.ms)))
            u32(12 + 10 * i, off)
            u32(16 + 10 * i, c.qoi.count)
            salida.replaceSubrange(off ..< off + c.qoi.count, with: c.qoi)
            off += c.qoi.count
        }
        return salida
    }

    static func esAnimacion(_ b: [UInt8]) -> Bool {
        b.count >= 10 && b[0] == 0x73 && b[1] == 0x61 && b[2] == 0x6E && b[3] == 0x69
    }

    /// Los cuadros (una imagen suelta es un cuadro de 0 ms).
    static func cuadros(_ b: [UInt8]) -> [Cuadro] {
        guard esAnimacion(b) else { return [Cuadro(qoi: b, ms: 0)] }
        func u16(_ p: Int) -> Int { Int(b[p]) | Int(b[p + 1]) << 8 }
        func u32(_ p: Int) -> Int { (0 ..< 4).reduce(0) { $0 | Int(b[p + $1]) << (8 * $1) } }
        return (0 ..< Int(b[5])).map { i in
            let off = u32(12 + 10 * i)
            return Cuadro(qoi: Array(b[off ..< off + u32(16 + 10 * i)]), ms: u16(10 + 10 * i))
        }
    }
}
