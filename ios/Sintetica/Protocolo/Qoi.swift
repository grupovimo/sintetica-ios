import Foundation

/// QOI ("Quite OK Image", https://qoiformat.org): el formato de las imágenes del
/// bicho. Igual que sim/web/qoi.js; los tests comparan los bytes contra
/// shared/protocolo/vectores.json.
enum Qoi {
    /// rgb: 3 bytes por píxel, fila por fila.
    static func codificar(_ rgb: [UInt8], ancho: Int, alto: Int) -> [UInt8] {
        var s: [UInt8] = [0x71, 0x6F, 0x69, 0x66]
        func u32(_ v: Int) { s += [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        u32(ancho); u32(alto); s += [3, 0]
        var indice = [Int](repeating: -1, count: 64)
        var pr = 0, pg = 0, pb = 0, racha = 0
        let total = ancho * alto
        s.reserveCapacity(total + 64)
        for i in 0 ..< total {
            let r = Int(rgb[i * 3]), g = Int(rgb[i * 3 + 1]), b = Int(rgb[i * 3 + 2])
            if r == pr, g == pg, b == pb {  // el "anterior" del primer píxel es negro, como en QOI
                racha += 1
                if racha == 62 || i == total - 1 { s.append(UInt8(0xC0 | (racha - 1))); racha = 0 }
                continue
            }
            if racha > 0 { s.append(UInt8(0xC0 | (racha - 1))); racha = 0 }
            let h = (r * 3 + g * 5 + b * 7 + 255 * 11) % 64
            let color = r << 16 | g << 8 | b
            if indice[h] == color {
                s.append(UInt8(h))
            } else {
                indice[h] = color
                let vr = Int(Int8(truncatingIfNeeded: r - pr)), vg = Int(Int8(truncatingIfNeeded: g - pg)), vb = Int(Int8(truncatingIfNeeded: b - pb))
                let vgr = vr - vg, vgb = vb - vg
                if (-2 ... 1).contains(vr), (-2 ... 1).contains(vg), (-2 ... 1).contains(vb) {
                    s.append(UInt8(0x40 | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2)))
                } else if (-8 ... 7).contains(vgr), (-32 ... 31).contains(vg), (-8 ... 7).contains(vgb) {
                    s += [UInt8(0x80 | (vg + 32)), UInt8((vgr + 8) << 4 | (vgb + 8))]
                } else {
                    s += [0xFE, UInt8(r), UInt8(g), UInt8(b)]
                }
            }
            pr = r; pg = g; pb = b
        }
        s += [0, 0, 0, 0, 0, 0, 0, 1]
        return s
    }
}
