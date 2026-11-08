import AVFoundation
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
    /// recortado para la miniatura.
    static func gif(_ datos: Data, ancho: Int, alto: Int, redonda: Bool) throws -> (bytes: [UInt8], primero: UIImage) {
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil), CGImageSourceGetCount(fuente) > 0 else {
            throw ErrorImagen.noEsGif
        }
        var cuadros: [(UIImage, Int)] = []
        for i in 0 ..< CGImageSourceGetCount(fuente) {
            guard let cg = CGImageSourceCreateImageAtIndex(fuente, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(fuente, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let segundos = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Como los navegadores: menos de 20 ms se toma como 100.
            cuadros.append((UIImage(cgImage: cg), segundos < 0.02 ? 100 : Int(segundos * 1000)))
        }
        return try empaquetar(cuadros, ancho: ancho, alto: alto, redonda: redonda)
    }

    /// Los cuadros (ya en orden, con su duración) recortados a la pantalla. Si
    /// no entran en un espacio (o son más de 64), se saltea uno de cada dos y el
    /// que queda dura lo de los dos, como la web.
    static func empaquetar(_ fuentes: [(UIImage, Int)], ancho: Int, alto: Int, redonda: Bool) throws -> (bytes: [UInt8], primero: UIImage) {
        var primero: UIImage?
        var cuadros: [Animacion.Cuadro] = []
        for (img, ms) in fuentes {
            let recortada = recortar(img, ancho: ancho, alto: alto, redonda: redonda)
            if primero == nil { primero = recortada }
            cuadros.append(Animacion.Cuadro(qoi: qoi(recortada), ms: ms))
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

    /// Un video corto: hasta 6 segundos desde el principio, a 12 cuadros por
    /// segundo como mucho (como web/src/lib/imagenes.ts).
    static let segundosVideo = 6.0
    static func cuadrosDeVideo(_ url: URL, ancho: Int, alto: Int) async throws -> [(UIImage, Int)] {
        let activo = AVURLAsset(url: url)
        let duracion = (try? await activo.load(.duration)).map { CMTimeGetSeconds($0) } ?? segundosVideo
        let dura = min(duracion.isFinite && duracion > 0 ? duracion : segundosVideo, segundosVideo)
        let paso = max(1.0 / 12, dura / Double(Animacion.maxCuadros))
        let ms = Int((paso * 1000).rounded())
        let generador = AVAssetImageGenerator(asset: activo)
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: ancho * 2, height: alto * 2)
        generador.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generador.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        var cuadros: [(UIImage, Int)] = []
        var t = 0.0
        while t < dura - 0.001, cuadros.count < Animacion.maxCuadros {
            let (cg, _) = try await generador.image(at: CMTime(seconds: t, preferredTimescale: 600))
            cuadros.append((UIImage(cgImage: cg), ms))
            t += paso
        }
        guard !cuadros.isEmpty else { throw ErrorImagen.videoVacio }
        return cuadros
    }

    /// Una imagen del robot (QOI o animación) en sus cuadros, como imágenes.
    static func cuadrosDe(_ bytes: [UInt8]) -> [(UIImage, Int)] {
        Animacion.cuadros(bytes).compactMap { c in Qoi.imagen(c.qoi).map { (UIImage(cgImage: $0), c.ms) } }
    }

    /// La misma imagen del robot a otro tamaño (para la vista previa al doble).
    static func reescalar(_ bytes: [UInt8], ancho: Int, alto: Int, redonda: Bool) -> [UInt8]? {
        let c = cuadrosDe(bytes)
        guard !c.isEmpty else { return nil }
        return try? empaquetar(c.map { ($0.0, max(20, $0.1)) }, ancho: ancho, alto: alto, redonda: redonda).bytes
    }

    enum ErrorImagen: LocalizedError {
        case noEsGif, muyPesado, videoVacio
        var errorDescription: String? {
            switch self {
            case .noEsGif: "No pude leer la imagen."
            case .muyPesado: "Muy pesado: probá uno más corto."
            case .videoVacio: "El video está vacío."
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
