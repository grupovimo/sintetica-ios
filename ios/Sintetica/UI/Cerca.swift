import Observation
import SwiftUI

/// Lo que se hace con el robot cerca, por Bluetooth: pasarle el WiFi, sumarlo a
/// la cuenta y actualizarle el firmware.
@MainActor
@Observable
final class ModeloCerca {
    let id: String
    var cliente: ClienteBicho?
    var propio = false
    var buscando = false
    var mensaje = ""
    var ocupado = false
    var firmwares: [FirmwareNube] = []
    var progresoOta: Double?

    init(id: String, cliente: ClienteBicho?) {
        self.id = id
        self.cliente = cliente
    }

    var estado: Estado? { cliente?.estado }

    func conectar() async {
        guard cliente == nil else { return }
        guard let v = Vinculados.compartidos.buscar(id) else { mensaje = "No está vinculado a este celu."; return }
        buscando = true
        defer { buscando = false }
        do {
            let p = try await Central.compartida.buscar(id: id, segundos: 12)
            let c = ClienteBicho(TransporteBle(p))
            try await c.conectar()
            try await c.autenticar(v.clave)
            cliente = c
            propio = true
        } catch {
            mensaje = error.localizedDescription
        }
    }

    func cerrar() { if propio { cliente?.cerrar() } }

    func configurarRed(_ ssid: String, _ clave: String) async {
        ocupado = true
        defer { ocupado = false }
        do { try await cliente?.configurarRed(ssid, clave: clave); mensaje = "Se conecta a «\(ssid)»." } catch { mensaje = error.localizedDescription }
    }

    func olvidarRed() async {
        do { try await cliente?.olvidarRed(); mensaje = "Olvidó el WiFi." } catch { mensaje = error.localizedDescription }
    }

    /// La API da credenciales nuevas, se las pasamos por BLE y, cuando el robot
    /// se conecta con ellas, queda en la cuenta.
    func sumarACuenta() async {
        guard let c = cliente else { return }
        ocupado = true
        defer { ocupado = false }
        do {
            let cuenta = Cuenta.compartida
            guard cuenta.activa else { throw ErrorBicho.rechazo("Entrá a tu cuenta.") }
            guard let e = c.estado, e.redConfigurada else { throw ErrorBicho.rechazo("Primero el WiFi.") }
            mensaje = "Pidiendo la clave…"
            let cred = try await cuenta.api.reclamar(id, perfil: e.perfil)
            try await c.configurarNube(url: cred.url, usuario: cred.usuario, clave: cred.clave)
            mensaje = "Esperando que se conecte…"
            mensaje = try await cuenta.api.esperarReclamo(id) ? "Listo: está en tu cuenta." : "No se conectó: revisá el WiFi."
        } catch {
            mensaje = error.localizedDescription
        }
    }

    func buscarFirmwares() async {
        let perfil = estado?.perfil ?? ""
        guard Cuenta.compartida.activa, !perfil.isEmpty else { mensaje = "Entrá a tu cuenta."; return }
        do {
            firmwares = try await Cuenta.compartida.api.firmwares(perfil: perfil)
            mensaje = firmwares.isEmpty ? "Está al día." : ""
        } catch { mensaje = error.localizedDescription }
    }

    func instalar(_ f: FirmwareNube) async {
        guard let c = cliente else { return }
        progresoOta = 0
        defer { progresoOta = nil }
        do {
            let api = Cuenta.compartida.api
            mensaje = "Bajando \(f.version)…"
            let man = try await api.manifiesto(f.id)
            let bin = try await api.binario(f.id)
            mensaje = "No lo alejes…"
            try await c.instalarFirmware(manifiesto: man, binario: bin) { [weak self] v in self?.progresoOta = v }
            mensaje = "Listo: reinicia con la \(f.version)."
        } catch {
            mensaje = error.localizedDescription
        }
    }
}

@MainActor
struct CercaVista: View {
    @State private var cerca: ModeloCerca
    @Environment(\.dismiss) private var cerrar
    @State private var ssid = ""
    @State private var clave = ""

    init(modelo: ModeloRobot) {
        _cerca = State(initialValue: ModeloCerca(id: modelo.id, cliente: modelo.esBle ? modelo.cliente : nil))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Grabado("Cerca · Bluetooth", color: .brasa)
                    Spacer()
                    Button { cerrar() } label: { Image(systemName: "xmark") }.tecla(.negra, cuadrada: true).accessibilityLabel("Cerrar")
                }
                Titular("Cerca", tamano: 40)
                if cerca.buscando {
                    HStack(spacing: 12) { ProgressView().tint(Color.brasa); Grabado("Buscando…") }
                } else if cerca.cliente == nil {
                    Button { Task { await cerca.conectar() } } label: { Label("Buscar", systemImage: "dot.radiowaves.left.and.right") }.tecla(.naranja, ancha: true)
                } else {
                    wifi
                    firmware
                }
                if !cerca.mensaje.isEmpty { AvisoConsola(texto: cerca.mensaje) }
            }
            .padding(20)
        }
        .background(FondoConsola())
        .presentationBackground(Color.fondo)
        .task { await cerca.conectar() }
        .onDisappear { cerca.cerrar() }
    }

    private var wifi: some View {
        let e = cerca.estado
        return PlacaNaranja {
            HStack {
                Grabado("WiFi y nube", color: Color.tinta.opacity(0.66))
                Spacer()
                Led(estado: e?.wifi == true ? .verde : e?.redConfigurada == true ? .ambar : .apagado)
                Led(estado: e?.nube == true ? .verde : .apagado)
            }
            CampoVisor(rotulo: "Red", texto: $ssid, ayuda: "Mi casa", claro: true, teclado: .asciiCapable)
            Visor(relleno: 12) {
                Grabado("Clave")
                SecureField("", text: $clave).font(Tipos.marca(18, .black)).foregroundStyle(Color.papel)
            }
            Button { Task { await cerca.configurarRed(ssid, clave) } } label: { Label("Pasarle el WiFi", systemImage: "wifi") }
                .tecla(ancha: true)
                .disabled(ssid.trimmingCharacters(in: .whitespaces).isEmpty || ssid.utf8.count > 32 || clave.utf8.count > 64 || cerca.ocupado)
            if Cuenta.compartida.activa {
                Button { Task { await cerca.sumarACuenta() } } label: { Label("Sumar a mi cuenta", systemImage: "icloud.and.arrow.up") }
                    .tecla(.negra, ancha: true).disabled(cerca.ocupado || e?.redConfigurada != true)
            }
            if e?.redConfigurada == true {
                Button { Task { await cerca.olvidarRed() } } label: { Text("Olvidar WiFi") }.tecla(.negra, chica: true)
            }
        }
    }

    private var firmware: some View {
        let e = cerca.estado
        return Visor {
            HStack {
                Grabado("Firmware")
                Spacer()
                Text((e?.version).flatMap { $0.isEmpty ? nil : $0 } ?? "—").font(Tipos.marca(14, .black)).foregroundStyle(Color.papel)
            }
            if cerca.firmwares.isEmpty {
                Button { Task { await cerca.buscarFirmwares() } } label: { Label("Buscar versiones", systemImage: "arrow.down.circle") }
                    .tecla(chica: true).disabled(cerca.progresoOta != nil)
            }
            ForEach(cerca.firmwares) { f in
                HStack {
                    Text("\(f.version) · \(f.tamano / 1024) KB").font(Tipos.marca(13, .bold)).foregroundStyle(Color.hueso)
                    Spacer()
                    Button { Task { await cerca.instalar(f) } } label: { Text(f.version == e?.version ? "Instalada" : "Instalar") }
                        .tecla(.naranja, chica: true).disabled(cerca.progresoOta != nil || f.version == e?.version)
                }
            }
            if let p = cerca.progresoOta { ProgressView(value: p).tint(Color.brasa) }
        }
    }
}
