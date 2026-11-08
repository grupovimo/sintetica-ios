import ImageIO
import UIKit

/// Recorta y escala una imagen a la pantalla del bicho, y la codifica en QOI.
enum PrepararImagen {
    /// Cubre la pantalla centrada (como un fondo de pantalla); si es redonda, fuera del círculo va negro.
    static func recortar(_ fuente: UIImage, ancho: Int, alto: Int, redonda: Bool) -> UIImage {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let tam = CGSize(width: ancho, height: alto)
        return UIGraphicsImageRenderer(size: tam, format: formato).image { ctx in
            UIColor(red: 11 / 255, green: 10 / 255, blue: 9 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: tam))
            if redonda { UIBezierPath(ovalIn: CGRect(origin: .zero, size: tam)).addClip() }
            let k = max(tam.width / fuente.size.width, tam.height / fuente.size.height)
            let w = fuente.size.width * k, h = fuente.size.height * k
            fuente.draw(in: CGRect(x: (tam.width - w) / 2, y: (tam.height - h) / 2, width: w, height: h))
        }
    }

    static func esGif(_ datos: Data) -> Bool { datos.starts(with: [0x47, 0x49, 0x46]) }

    /// Un GIF a la pantalla: cada cuadro recortado como una foto, en una
    /// animación "sani" (o un QOI si tiene un solo cuadro), y el primer cuadro
    /// recortado para la miniatura. Si no entra en un espacio, se saltea uno de
    /// cada dos cuadros y el que queda dura lo de los dos, como la web.
    static func gif(_ datos: Data, ancho: Int, alto: Int, redonda: Bool) throws -> (bytes: [UInt8], primero: UIImage) {
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil), CGImageSourceGetCount(fuente) > 0 else {
            throw ErrorImagen.noEsGif
        }
        var cuadros: [Animacion.Cuadro] = []
        var primero: UIImage?
        for i in 0 ..< CGImageSourceGetCount(fuente) {
            guard let cg = CGImageSourceCreateImageAtIndex(fuente, i, nil) else { continue }
            let recortada = recortar(UIImage(cgImage: cg), ancho: ancho, alto: alto, redonda: redonda)
            if primero == nil { primero = recortada }
            let props = CGImageSourceCopyPropertiesAtIndex(fuente, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let segundos = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Como los navegadores: menos de 20 ms se toma como 100.
            cuadros.append(Animacion.Cuadro(qoi: qoi(recortada), ms: segundos < 0.02 ? 100 : Int(segundos * 1000)))
        }
        guard let primero, !cuadros.isEmpty else { throw ErrorImagen.noEsGif }
        if cuadros.count == 1 { return (cuadros[0].qoi, primero) }
        let limite = ancho * alto * 4 + 22
        var sani = Animacion.codificar(Array(cuadros.prefix(Animacion.maxCuadros)), ancho: ancho, alto: alto)
        while cuadros.count > Animacion.maxCuadros || sani.count > limite {
            guard cuadros.count > 2 else { throw ErrorImagen.muyPesado }
            cuadros = stride(from: 0, to: cuadros.count, by: 2).map { i in
                Animacion.Cuadro(qoi: cuadros[i].qoi, ms: cuadros[i].ms + (i + 1 < cuadros.count ? cuadros[i + 1].ms : 0))
            }
            sani = Animacion.codificar(Array(cuadros.prefix(Animacion.maxCuadros)), ancho: ancho, alto: alto)
        }
        return (sani, primero)
    }

    enum ErrorImagen: LocalizedError {
        case noEsGif, muyPesado
        var errorDescription: String? {
            switch self {
            case .noEsGif: "No pude leer el GIF."
            case .muyPesado: "El GIF es demasiado pesado para la pantalla: probá con uno más simple."
            }
        }
    }

    static func qoi(_ imagen: UIImage) -> [UInt8] {
        guard let cg = imagen.cgImage else { return [] }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0 ..< w * h {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return Qoi.codificar(rgb, ancho: w, alto: h)
    }
}

/// Las imágenes que este celu le mandó a cada bicho (el bicho no las devuelve):
/// la que se mandó, una al doble para la vista previa y una miniatura.
enum CacheImagenes {
    private static var raiz: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("imagenes")
    }

    private static func url(_ id: String, _ espacio: Int, _ sufijo: String) -> URL {
        raiz.appendingPathComponent(id).appendingPathComponent("\(espacio)\(sufijo)")
    }

    static func guardar(_ id: String, _ espacio: Int, mandada: [UInt8], vistaPrevia: [UInt8], miniatura: UIImage) {
        let carpeta = raiz.appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try? Data(mandada).write(to: url(id, espacio, ".qoi"))
        try? Data(vistaPrevia).write(to: url(id, espacio, "-vista.qoi"))
        try? miniatura.pngData()?.write(to: url(id, espacio, ".png"))
    }

    static func mandada(_ id: String, _ espacio: Int) -> [UInt8]? { (try? Data(contentsOf: url(id, espacio, ".qoi"))).map { Array($0) } }
    static func vistaPrevia(_ id: String, _ espacio: Int) -> [UInt8]? { (try? Data(contentsOf: url(id, espacio, "-vista.qoi"))).map { Array($0) } }
    static func miniatura(_ id: String, _ espacio: Int) -> UIImage? { UIImage(contentsOfFile: url(id, espacio, ".png").path) }

    static func borrar(_ id: String, _ espacio: Int) {
        for s in [".qoi", "-vista.qoi", ".png"] { try? FileManager.default.removeItem(at: url(id, espacio, s)) }
    }
}
