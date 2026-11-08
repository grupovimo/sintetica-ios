import SwiftUI

@MainActor
struct Inicio: View {
    @Binding var ruta: [Ruta]
    private var vinculados = Vinculados.compartidos
    private var cuenta = Cuenta.compartida
    @State private var enLaNube: [BichoNube] = []

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Etiqueta("Sintética Labs")
                Text(vinculados.todos.isEmpty ? "Hola." : "Tus bichos").font(Tipos.display).foregroundStyle(Color.tinta)
            }
            if vinculados.todos.isEmpty {
                Text("Prendé tu bicho: en la pantalla va a aparecer un QR. Escanealo para vincularlo con este celu.")
                    .font(Tipos.cuerpo).foregroundStyle(Color.tintaSuave)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let lejos = enLaNube.filter { n in !vinculados.todos.contains { $0.id == n.id } }
                    if !lejos.isEmpty { Etiqueta("En tu cuenta (por la nube)") }
                    ForEach(lejos) { b in
                        Button { ruta.append(.bicho(PREFIJO_NUBE + b.id)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.conectado ? "CONECTADO" : "DESCONECTADO").font(Tipos.serie)
                                    .foregroundStyle(b.conectado ? Color.naranjaProfundo : Color.tintaSuave)
                                Text(b.nombre).font(Tipos.titulo).foregroundStyle(Color.tinta)
                                Text("\(b.id) · \(b.perfil)\(b.virtual ? " · virtual" : "")").font(Tipos.dato).foregroundStyle(Color.tintaSuave)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(Color.papelAlto, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.linea, lineWidth: 1))
                        }
                    }
                    if !lejos.isEmpty && !vinculados.todos.isEmpty { Etiqueta("Cerca (por BLE)") }
                    ForEach(vinculados.todos) { b in
                        Button { ruta.append(.bicho(b.id)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("UNIDAD #\(b.serie.isEmpty ? "—" : b.serie)").font(Tipos.serie).foregroundStyle(Color.naranjaProfundo)
                                Text(b.nombre).font(Tipos.titulo).foregroundStyle(Color.tinta)
                                Text(b.id).font(Tipos.dato).foregroundStyle(Color.tintaSuave)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(Color.papelAlto, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.linea, lineWidth: 1))
                        }
                    }
                }
            }
            BotonPrimario(texto: "Vincular un bicho") { ruta.append(.escanear) }
            BotonSecundario(texto: cuenta.activa ? "Tu cuenta" : "Entrar a tu cuenta") { ruta.append(.cuenta) }
            HStack(spacing: 8) {
                BotonSecundario(texto: "Probar sin bicho") { ruta.append(.bicho(ID_DEMO)) }
                BotonSecundario(texto: "Probar el broche") { ruta.append(.bicho(ID_DEMO_BROCHE)) }
            }
        }
        .padding(24)
        .background(Color.papel.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: cuenta.activa) {
            guard cuenta.activa else { enLaNube = []; return }
            do { enLaNube = try await cuenta.api.bichos() } catch let e as ErrorApi where e.estado == 401 { cuenta.salir() } catch {}
        }
    }
}
