@preconcurrency import AVFoundation
import SwiftUI

@MainActor
struct Escanear: View {
    @Binding var ruta: [Ruta]
    @State private var aviso: String?
    @State private var permiso = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Etiqueta("Vincular")
            Text("Escaneá el QR de la pantalla del bicho.").font(Tipos.titulo).foregroundStyle(Color.tinta)
            ZStack {
                Color.pantalla
                if permiso == .authorized {
                    Camara { texto in
                        if let qr = leerQr(texto) { ruta = [.vinculando(qr)] } else { aviso = "Ese QR no es de un bicho de Sintética Labs." }
                    }
                } else {
                    Text("Para escanear hace falta la cámara (Ajustes › Sintética).").font(Tipos.chico).foregroundStyle(Color.tintaSuave).padding(24)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            if let aviso { Aviso(texto: aviso) }
            Text("¿No ves el QR? Si el bicho ya está vinculado con otro celu, mantené apretado el botón 5 segundos.")
                .font(Tipos.chico).foregroundStyle(Color.tintaSuave)
            Spacer()
        }
        .padding(24)
        .background(Color.papel.ignoresSafeArea())
        .task {
            if permiso == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permiso = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

/// Vista de la cámara que lee códigos QR con AVFoundation.
private struct Camara: UIViewRepresentable {
    let alLeer: (String) -> Void

    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var capa: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinador: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let sesion = AVCaptureSession()
        var alLeer: (String) -> Void = { _ in }
        private var leido = false

        func metadataOutput(_ salida: AVCaptureMetadataOutput, didOutput objetos: [AVMetadataObject], from conexion: AVCaptureConnection) {
            guard !leido, let t = (objetos.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            if leerQr(t) != nil { leido = true }
            alLeer(t)
        }
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeUIView(context: Context) -> Vista {
        let v = Vista()
        let c = context.coordinator
        c.alLeer = alLeer
        v.capa.session = c.sesion
        v.capa.videoGravity = .resizeAspectFill
        if let camara = AVCaptureDevice.default(for: .video), let entrada = try? AVCaptureDeviceInput(device: camara), c.sesion.canAddInput(entrada) {
            c.sesion.addInput(entrada)
            let salida = AVCaptureMetadataOutput()
            if c.sesion.canAddOutput(salida) {
                c.sesion.addOutput(salida)
                salida.setMetadataObjectsDelegate(c, queue: .main)
                salida.metadataObjectTypes = [.qr]
            }
            DispatchQueue.global(qos: .userInitiated).async { c.sesion.startRunning() }
        }
        return v
    }

    func updateUIView(_ v: Vista, context: Context) {}

    static func dismantleUIView(_ v: Vista, coordinator: Coordinador) { coordinator.sesion.stopRunning() }
}
