import UIKit

// Las caras de imagen (docs/motor-de-vida.md, "Caras de imagen"): ojos y boca
// con sprites (0 a 11), en los espacios 8 a 19 de la característica Imagen.

let PARTES_SPRITE = ["ojo", "ojo_cerrado", "boca", "ojo_der", "ojo_der_cerrado"]

/// Una expresión es de imagen si tiene "sprites" (un objeto).
func esImagen(_ doc: Any?) -> Bool { (doc as? [String: Any])?["sprites"] is [String: Any] }

extension ConfigDoc {
    /// Las caras de imagen de la config, por nombre.
    var deImagen: [String] { expresiones.filter { esImagen($0.value) }.keys.sorted() }

    /// El sprite de una parte de una cara de imagen.
    func sprite(_ cara: String, _ parte: String) -> Int? {
        ((expresiones[cara] as? [String: Any])?["sprites"] as? [String: Any])?[parte].flatMap { ($0 as? NSNumber)?.intValue }
    }

    /// Los sprites que usa cada cara de imagen (menos la que se está editando).
    func spritesEnUso(menos: String = "") -> Set<Int> {
        var l = Set<Int>()
        for (n, e) in expresiones where n != menos && esImagen(e) {
            for (_, x) in ((e as? [String: Any])?["sprites"] as? [String: Any]) ?? [:] { if let v = (x as? NSNumber)?.intValue { l.insert(v) } }
        }
        return l
    }

    /// La cara de siempre ("cara": {"expresion": …}); vacío = la de fábrica.
    var caraSiempre: String { (raiz["cara"] as? [String: Any])?["expresion"] as? String ?? "" }

    mutating func ponerCaraSiempre(_ n: String) {
        var c = raiz["cara"] as? [String: Any] ?? [:]
        if n.isEmpty { c.removeValue(forKey: "expresion") } else { c["expresion"] = n }
        if c.isEmpty { raiz.removeValue(forKey: "cara") } else { raiz["cara"] = c }
    }
}

/// Un sprite libre: ni de otra cara de imagen ni de otra parte de esta.
func spriteLibre(usados: Set<Int>) -> Int? {
    (0 ..< Op.maxSprites).first { !usados.contains($0) }
}

/// Un dibujo a sprite (para los robots cerca: por la nube lo hace la API):
/// recortado a lo que no es transparente, achicado a 128 × 128 como mucho y en
/// QOI de 4 canales.
enum PrepararSprite {
    static let lado = 128

    static func qoi(_ fuente: UIImage) -> [UInt8]? {
        guard let cg = fuente.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let listo = px.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard listo else { return nil }
        // La caja de lo que se ve.
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        for y in 0 ..< h {
            for x in 0 ..< w where px[(y * w + x) * 4 + 3] > 8 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        if x1 < 0 { x0 = 0; y0 = 0; x1 = w - 1; y1 = h - 1 }
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        guard let recorte = cg.cropping(to: CGRect(x: x0, y: y0, width: cw, height: ch)) else { return nil }
        let k = min(1, Double(lado) / Double(max(cw, ch)))
        let dw = max(1, Int((Double(cw) * k).rounded())), dh = max(1, Int((Double(ch) * k).rounded()))
        var sal = [UInt8](repeating: 0, count: dw * dh * 4)
        let ok = sal.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: dw, height: dh, bitsPerComponent: 8, bytesPerRow: dw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(recorte, in: CGRect(x: 0, y: 0, width: dw, height: dh))
            return true
        }
        guard ok else { return nil }
        // De premultiplicado a recto (QOI guarda el color sin multiplicar).
        for i in 0 ..< dw * dh {
            let a = Int(sal[i * 4 + 3])
            if a == 0 { sal[i * 4] = 0; sal[i * 4 + 1] = 0; sal[i * 4 + 2] = 0; continue }
            if a < 255 {
                for c in 0 ..< 3 { sal[i * 4 + c] = UInt8(min(255, Int(sal[i * 4 + c]) * 255 / a)) }
            }
        }
        return Qoi.codificarRGBA(sal, ancho: dw, alto: dh)
    }
}
