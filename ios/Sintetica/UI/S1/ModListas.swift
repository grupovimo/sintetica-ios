import SwiftUI

/// 12 · Listas: la del súper, pendientes o la que sea. Son de la cuenta (no
/// de la S1): lo que anotás acá ella lo ve, y también charlando ("anotá
/// yerba"). Como web/src/lib/consola/modulos/Listas.svelte.
@MainActor
struct ModListas: View {
    let sesion: SesionS1
    @State private var listas: [ListaNube] = []
    @State private var porDefecto = "súper"
    @State private var elegida = ""
    @State private var nuevo = ""
    @State private var cargando = true
    @State private var errorCarga = false
    /// Lo que no se pudo anotar (para "Reintentar").
    @State private var noSeGuardo: String?
    @State private var oyente: UUID?
    @FocusState private var escribiendo: Bool

    private var api: ApiSintetica { Cuenta.compartida.api }
    private var lista: ListaNube? { listas.first { $0.id == elegida } ?? listas.first }

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if cargando {
                    EstadoCargando(renglones: 4)
                } else if errorCarga {
                    EstadoError(texto: "No pude traer las listas.") { Task { await cargar() } }
                } else {
                    contenido
                }
            }
            .task { await cargar() }
            .onChange(of: lista, initial: true) { _, l in
                sesion.listaEnPantalla = l.map { ($0.nombre.capitalized, $0.items.filter { !$0.hecho }.map(\.texto)) }
            }
            .onAppear {
                oyente = EnVivo.compartido.escuchar { e in
                    if e.tipo == "listas" { Task { await cargar() } }
                }
            }
            .onDisappear { if let o = oyente { EnVivo.compartido.dejar(o) } }
        }
    }

    @ViewBuilder private var contenido: some View {
        if listas.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(listas) { l in
                        ChipS1(l.nombre.capitalized, elegido: l.id == lista?.id) { elegida = l.id }
                    }
                }
            }
        }
        agregar
        if let n = noSeGuardo {
            EstadoError(texto: "No se guardó «\(n)».") {
                nuevo = n
                noSeGuardo = nil
                Task { await anotar() }
            }
        }
        let items = lista?.items ?? []
        let pendientes = items.filter { !$0.hecho }
        let tachadas = items.filter(\.hecho)
        if items.isEmpty, noSeGuardo == nil {
            EstadoVacio(texto: "Nada por comprar.")
        } else {
            VStack(spacing: 0) {
                ForEach(pendientes + tachadas) { i in renglon(i) }
            }
            if !tachadas.isEmpty {
                Button { Task { await limpiar() } } label: { Text("Sacar las tachadas") }.tecla(ancha: true)
            }
        }
    }

    private var agregar: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let vacio = nuevo.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $nuevo, prompt: Text("Anotá algo").foregroundColor(Color.s1Tinta3))
                .font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).tint(Color.s1Naranja)
                .focused($escribiendo)
                .submitLabel(.done)
                .onSubmit { Task { await anotar() } }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(forma.fill(Color.s1Campo))
                .overlay(forma.strokeBorder(escribiendo ? Color.s1Tinta : Color.s1Linea, lineWidth: escribiendo ? 2 : 1))
            Button { Task { await anotar() } } label: { IconoS1(.sumar, tamano: 22).frame(width: 48, height: 48) }
                .buttonStyle(EstiloRelieve(naranja: true))
                .disabled(vacio)
                .accessibilityLabel("Anotar")
        }
    }

    private func renglon(_ i: ItemLista) -> some View {
        HStack(spacing: 12) {
            Button { Task { await tachar(i) } } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(i.hecho ? Color.s1Inv : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(i.hecho ? Color.s1Inv : Color.s1Tinta2, lineWidth: 2)
                    if i.hecho { IconoS1(.check, tamano: 18).foregroundStyle(Color.s1InvTexto) }
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(i.hecho ? "Destachar \(i.texto)" : "Tachar \(i.texto)")
            Text(i.texto).font(S1Tipo.cuerpo)
                .foregroundStyle(i.hecho ? Color.s1Tinta2 : Color.s1Tinta)
                .strikethrough(i.hecho)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button { Task { await sacar(i) } } label: {
                IconoS1(.menos, tamano: 20).foregroundStyle(Color.s1Tinta2).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sacar \(i.texto)")
        }
        .frame(minHeight: 56)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
    }

    // --- La nube ---

    private func cargar() async {
        do {
            let r = try await api.listas()
            listas = r.listas
            porDefecto = r.porDefecto
            errorCarga = false
        } catch {
            if listas.isEmpty { errorCarga = true }
        }
        cargando = false
    }

    private func reemplazar(_ l: ListaNube) {
        if let k = listas.firstIndex(where: { $0.id == l.id }) { listas[k] = l } else { listas.append(l) }
    }

    /// Sin listas, la primera cosa crea la del súper.
    private func listaActual() async throws -> ListaNube {
        if let l = lista { return l }
        let l = try await api.crearLista(porDefecto)
        reemplazar(l)
        elegida = l.id
        return l
    }

    private func anotar() async {
        let t = nuevo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        nuevo = ""
        do {
            let l = try await listaActual()
            let nueva = try await api.agregarALista(l.id, t)
            reemplazar(nueva)
            noSeGuardo = nil
        } catch {
            noSeGuardo = t
        }
    }

    private func tachar(_ i: ItemLista) async {
        guard let l = lista, let k = listas.firstIndex(where: { $0.id == l.id }),
              let j = listas[k].items.firstIndex(where: { $0.id == i.id }) else { return }
        listas[k].items[j].hecho.toggle()
        let hecho = listas[k].items[j].hecho
        do {
            try await api.tacharEnLista(l.id, item: i.id, hecho: hecho)
        } catch {
            if let k2 = listas.firstIndex(where: { $0.id == l.id }), let j2 = listas[k2].items.firstIndex(where: { $0.id == i.id }) {
                listas[k2].items[j2].hecho = !hecho
            }
        }
    }

    private func sacar(_ i: ItemLista) async {
        guard let l = lista else { return }
        do {
            try await api.sacarDeLista(l.id, item: i.id)
            if let k = listas.firstIndex(where: { $0.id == l.id }) { listas[k].items.removeAll { $0.id == i.id } }
        } catch {}
    }

    private func limpiar() async {
        guard let l = lista else { return }
        if let r = try? await api.limpiarLista(l.id) { reemplazar(r) }
    }
}
