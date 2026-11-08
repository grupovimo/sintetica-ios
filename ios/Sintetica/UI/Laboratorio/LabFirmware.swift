import SwiftUI

/// Firmware por WiFi (la nube se lo manda): la versión que tiene, las que hay
/// (instalar pide "¿Seguro?" en dos toques) y lo que pasó. Sin nombre de placa:
/// solo el modelo. Como web/src/routes/robots/[id]/actualizar/+page.svelte.
@MainActor
struct LabFirmware: View {
    let modelo: ModeloRobot
    let cerca: () -> Void
    @State private var versiones: [VersionFirmware] = []
    @State private var historial: [Actualizacion] = []
    @State private var seguro = 0
    @State private var mandando = 0
    @State private var error = ""

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        let e = modelo.estado
        let actual = (e?.version).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let puede = modelo.esNube && modelo.conectado && e?.wifi == true && e?.actualizando != true
        VStack(alignment: .leading, spacing: 18) {
            PlacaNaranja {
                Visor(relleno: 14) {
                    Grabado("\(modelo.producto.nombre) · tiene")
                    Digitos(texto: actual)
                }
                if e?.wifi != true || !modelo.esNube {
                    HStack {
                        Label("Sin WiFi: desde cerca", systemImage: "wifi.slash").font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8))
                        Spacer()
                        if modelo.vinculado || modelo.esBle {
                            Button(action: cerca) { Label("Cerca", systemImage: "dot.radiowaves.left.and.right") }.tecla(.negra, chica: true)
                        }
                    }
                }
                if !error.isEmpty { AvisoConsola(texto: error, error: true) }
                if versiones.isEmpty {
                    Bandeja { Text("Está al día.").font(Tipos.texto).foregroundStyle(Color.tinta.opacity(0.8)) }
                }
                ForEach(versiones) { f in fila(f, actual: actual, puede: puede) }
            }
            if !historial.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Grabado("Historial")
                    ForEach(historial) { h in filaHistorial(h) }
                }
                .padding(18)
                .chapa()
            }
        }
        .task { await cargar() }
        .onChange(of: modelo.ota) { _, o in
            guard let o else { return }
            if let i = historial.firstIndex(where: { $0.id == o.id }) { historial[i] = o } else { historial.insert(o, at: 0) }
        }
    }

    private func cargar() async {
        guard modelo.esNube, !modelo.perfil.isEmpty else { return }
        versiones = (try? await api.versionesFirmware(perfil: modelo.perfil)) ?? []
        historial = (try? await api.actualizaciones(modelo.id)) ?? []
    }

    private func fila(_ f: VersionFirmware, actual: String, puede: Bool) -> some View {
        let es = f.version == actual
        let texto: String = es ? "Instalada" : mandando == f.id ? "Mandando…" : seguro == f.id ? "¿Seguro?" : "Instalar"
        return Bandeja(relleno: 14, espacio: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.version).font(Tipos.marca(20, .black)).foregroundStyle(Color.tinta)
                    if let c = f.creado { Grabado(c.formatted(date: .abbreviated, time: .omitted), color: Color.tinta.opacity(0.6)) }
                }
                Spacer()
                Button { instalar(f) } label: { Text(texto) }
                    .tecla(seguro == f.id ? .naranja : .negra, chica: true)
                    .disabled(es || !puede || mandando > 0)
            }
            if !f.notas.isEmpty { Text(f.notas).font(Tipos.chico).foregroundStyle(Color.tinta.opacity(0.8)).lineLimit(3) }
        }
    }

    private func filaHistorial(_ h: Actualizacion) -> some View {
        let led: EstadoLed = h.estado == "confirmada" ? .verde : h.estado == "fallida" ? .rojo : .on
        return HStack(spacing: 10) {
            Led(estado: led)
            Text(h.version).font(Tipos.marca(13, .black)).foregroundStyle(Color.papel)
            Text(h.nombreEstado.uppercased()).font(Tipos.marca(10, .heavy)).foregroundStyle(h.estado == "fallida" ? Color.rojo : Color.grisClaro)
            if h.estado == "descargando" { ProgressView(value: Double(h.progreso), total: 100).tint(Color.brasa) }
            Spacer(minLength: 0)
            Text(h.creada.map { hace($0) } ?? "").font(Tipos.chico).foregroundStyle(Color.gris)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.hundido))
    }

    private func instalar(_ f: VersionFirmware) {
        guard seguro == f.id else {
            seguro = f.id
            Task { try? await Task.sleep(for: .seconds(5)); if seguro == f.id { seguro = 0 } }
            return
        }
        seguro = 0
        mandando = f.id
        error = ""
        Task {
            do {
                let u = try await api.actualizar(modelo.id, firmware: f.id)
                historial.insert(u, at: 0)
            } catch {
                self.error = error.localizedDescription
            }
            mandando = 0
        }
    }
}

/// Historial de la config: una línea de tiempo con "↺ Volver". Como
/// web/src/routes/robots/[id]/historial/+page.svelte.
@MainActor
struct LabHistorial: View {
    let modelo: ModeloRobot
    @State private var versiones: [VersionConfig] = []
    @State private var aviso = ""

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Grabado("Cambios")
                Spacer()
                if !aviso.isEmpty { Grabado(aviso, color: .verde) }
            }
            .padding(.bottom, 14)
            if !modelo.esNube {
                Text("Solo con la nube.").font(Tipos.texto).foregroundStyle(Color.gris)
            }
            ForEach(Array(versiones.enumerated()), id: \.element.id) { i, v in punto(v, ultimo: i == versiones.count - 1) }
        }
        .padding(20)
        .chapa()
        .task(id: modelo.versionConfig) { await cargar() }
    }

    private func cargar() async {
        guard modelo.esNube else { return }
        versiones = (try? await api.historialConfig(modelo.id)) ?? []
    }

    private func punto(_ v: VersionConfig, ultimo: Bool) -> some View {
        let es = v.version == modelo.versionConfig
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(es ? Color.led : Color(hex: 0x4A443E)).frame(width: 12, height: 12).shadow(color: es ? Color.led : .clear, radius: 5)
                    .padding(.top, 14)
                if !ultimo { Rectangle().fill(Color(hex: 0x3A3632)).frame(width: 2) }
            }
            .frame(width: 14)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("v\(v.version)").font(Tipos.marca(17, .black)).foregroundStyle(Color.papel)
                        Text(v.nombreAutor.uppercased()).font(Tipos.marca(10, .heavy)).foregroundStyle(Color.grisClaro).lineLimit(1)
                    }
                    Text(v.creada.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "").font(Tipos.chico).foregroundStyle(Color.gris)
                }
                Spacer()
                if es {
                    Grabado("Actual", color: .brasa)
                } else {
                    Button { volver(v.version) } label: { Label("Volver", systemImage: "arrow.uturn.backward") }.tecla(chica: true)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func volver(_ v: Int) {
        Task {
            do {
                try await api.restaurarConfig(modelo.id, version: v)
                await modelo.recargarConfig()
                await cargar()
                aviso = "Volviste a la v\(v)"
            } catch {
                aviso = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(3))
            aviso = ""
        }
    }
}
