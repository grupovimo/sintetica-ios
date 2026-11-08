import Foundation

/// QOI ("Quite OK Image", https://qoiformat.org): el formato de las imágenes del
/// bicho. Igual que sim/web/qoi.js; los tests comparan los bytes contra
/// shared/protocolo/vectores.json.
enum Qoi {
    /// rgb: 3 bytes por píxel, fila por fila.
    static func codificar(_ rgb: [UInt8], ancho: Int, alto: Int) -> [UInt8] {
        var s: [UInt8] = [0x71, 0x6F, 0x69, 0x66]
        // Expresiones partidas en pasos con tipo: el Xcode del CI no llega a
        // inferir los tipos de las largas a tiempo.
        func u32(_ v: Int) { for k in [24, 16, 8, 0] { s.append(UInt8((v >> k) & 255)) } }
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
            let suma: Int = r * 3 + g * 5 + b * 7 + 2805  // + a·11, con a = 255
            let h: Int = suma % 64
            let color: Int = (r << 16) | (g << 8) | b
            if indice[h] == color {
                s.append(UInt8(h))
            } else {
                indice[h] = color
                let vr = Int(Int8(truncatingIfNeeded: r - pr)), vg = Int(Int8(truncatingIfNeeded: g - pg)), vb = Int(Int8(truncatingIfNeeded: b - pb))
                let vgr = vr - vg, vgb = vb - vg
                if (-2 ... 1).contains(vr), (-2 ... 1).contains(vg), (-2 ... 1).contains(vb) {
                    let d: Int = 0x40 | ((vr + 2) << 4) | ((vg + 2) << 2) | (vb + 2)
                    s.append(UInt8(d))
                } else if (-8 ... 7).contains(vgr), (-32 ... 31).contains(vg), (-8 ... 7).contains(vgb) {
                    let l1: Int = 0x80 | (vg + 32)
                    let l2: Int = ((vgr + 8) << 4) | (vgb + 8)
                    s.append(UInt8(l1))
                    s.append(UInt8(l2))
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
