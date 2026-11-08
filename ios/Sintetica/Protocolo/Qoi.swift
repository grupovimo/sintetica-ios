import CoreGraphics
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

    /// Al revés: los píxeles (rgb, 3 bytes por píxel) de un QOI, o nil si no es uno.
    static func decodificar(_ b: [UInt8]) -> (ancho: Int, alto: Int, rgb: [UInt8])? {
        guard b.count >= 22, b[0] == 0x71, b[1] == 0x6F, b[2] == 0x69, b[3] == 0x66 else { return nil }
        func u32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
        let ancho = u32(4), alto = u32(8)
        guard ancho > 0, alto > 0, ancho <= 4096, alto <= 4096 else { return nil }
        let total = ancho * alto
        var rgb = [UInt8](repeating: 0, count: total * 3)
        var indice = [Int](repeating: 0, count: 64 * 4)
        var r = 0, g = 0, bl = 0, a = 255
        var p = 14, racha = 0
        let fin = b.count - 8
        for i in 0 ..< total {
            if racha > 0 {
                racha -= 1
            } else if p < fin {
                let op = Int(b[p]); p += 1
                if op == 0xFE {
                    r = Int(b[p]); g = Int(b[p + 1]); bl = Int(b[p + 2]); p += 3
                } else if op == 0xFF {
                    r = Int(b[p]); g = Int(b[p + 1]); bl = Int(b[p + 2]); a = Int(b[p + 3]); p += 4
                } else if op >> 6 == 0 {
                    let k = op * 4
                    r = indice[k]; g = indice[k + 1]; bl = indice[k + 2]; a = indice[k + 3]
                } else if op >> 6 == 1 {
                    r = (r + (op >> 4 & 3) - 2) & 255
                    g = (g + (op >> 2 & 3) - 2) & 255
                    bl = (bl + (op & 3) - 2) & 255
                } else if op >> 6 == 2 {
                    let dg = (op & 63) - 32
                    let s2 = Int(b[p]); p += 1
                    r = (r + dg + (s2 >> 4 & 15) - 8) & 255
                    g = (g + dg) & 255
                    bl = (bl + dg + (s2 & 15) - 8) & 255
                } else {
                    racha = op & 63
                }
                let h: Int = (r * 3 + g * 5 + bl * 7 + a * 11) % 64
                indice[h * 4] = r; indice[h * 4 + 1] = g; indice[h * 4 + 2] = bl; indice[h * 4 + 3] = a
            }
            rgb[i * 3] = UInt8(r); rgb[i * 3 + 1] = UInt8(g); rgb[i * 3 + 2] = UInt8(bl)
        }
        return (ancho, alto, rgb)
    }

    /// Un QOI como imagen.
    static func imagen(_ b: [UInt8]) -> CGImage? {
        guard let d = decodificar(b) else { return nil }
        var rgba = [UInt8](repeating: 255, count: d.ancho * d.alto * 4)
        for i in 0 ..< d.ancho * d.alto {
            rgba[i * 4] = d.rgb[i * 3]; rgba[i * 4 + 1] = d.rgb[i * 3 + 1]; rgba[i * 4 + 2] = d.rgb[i * 3 + 2]
        }
        guard let proveedor = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: d.ancho, height: d.alto, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: d.ancho * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: proveedor, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
