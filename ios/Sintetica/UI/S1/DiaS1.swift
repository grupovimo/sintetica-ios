import SwiftUI

// 17 · Rutinas, 18 · El diario, 25 · Memoria, 26 · Agenda y 27 · Hábitos.

/// Una rutina para sumar de un toque.
private struct RutinaSugerida: Identifiable {
    let id: String
    let titulo: String
    let detalle: String
    let crear: () -> Automatizacion
}

private func nuevoId(_ k: String) -> String { "a" + k + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) }

/// 17 · Rutinas: lo que hace sola a una hora (o cuando pasa algo), con su
/// toggle; las sugeridas para sumar y "Nueva rutina".
@MainActor
struct RutinasS1: View {
    let sesion: SesionS1
    @State private var autos: [Automatizacion] = []
    @State private var cargando = true
    @State private var fallo = false
    @State private var abierta: String?
    @State private var reloj: Task<Void, Never>?
    @State private var error = ""

    private var api: ApiSintetica { Cuenta.compartida.api }

    private static let sugeridas: [RutinaSugerida] = [
        RutinaSugerida(id: "buen-dia", titulo: "Buen día", detalle: "07:30 · la hora, el clima y lo que tenés hoy") {
            Automatizacion(id: nuevoId("bd"), activa: true, cuando: "hora", hora: "07:30",
                           hacer: [AccionAuto(tipo: "decir", texto: "{clima}. {hoy}")])
        },
        RutinaSugerida(id: "llego", titulo: "Cuando llego a casa", detalle: "Te saluda y te cuenta lo pendiente") {
            Automatizacion(id: nuevoId("ll"), activa: true, cuando: "llegaste", hacer: [AccionAuto(tipo: "decir", texto: "¡Hola, {dueno}! {hoy}")])
        },
        RutinaSugerida(id: "pizza", titulo: "Viernes de pizza", detalle: "Viernes 20:30 · te pregunta qué pedir") {
            Automatizacion(id: nuevoId("pz"), activa: true, cuando: "hora", hora: "20:30", dias: "V",
                           hacer: [AccionAuto(tipo: "decir", texto: "¿Pedimos pizza?")])
        },
        RutinaSugerida(id: "dormir", titulo: "A dormir", detalle: "22:30 · pasa al reloj") {
            Automatizacion(id: nuevoId("ad"), activa: true, cuando: "hora", hora: "22:30",
                           hacer: [AccionAuto(tipo: "decir", texto: "Hasta mañana, {dueno}"), AccionAuto(tipo: "modo", modo: "reloj")])
        },
    ]

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if cargando {
            EstadoCargando(renglones: 4).task { await cargar() }
        } else if fallo {
            EstadoError(texto: "No pude ver sus rutinas.") { Task { await cargar() } }
        } else {
            contenido
        }
    }

    @ViewBuilder private var contenido: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !error.isEmpty { AvisoConsola(texto: error, error: true).padding(.bottom, 12) }
            if autos.isEmpty {
                EstadoVacio(texto: "Todavía sin rutinas.", expresion: "pensando")
            } else {
                VStack(spacing: 0) {
                    ForEach(autos.indices, id: \.self) { i in fila(i) }
                }
            }
            let faltan = Self.sugeridas.filter { s in !autos.contains { titulo($0) == s.titulo || ($0.cuando == "llegaste" && s.id == "llego") } }
            if !faltan.isEmpty {
                Seccion("Para sumar")
                VStack(spacing: 0) {
                    ForEach(faltan) { s in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                                Text(s.detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Button { sumar(s.crear(), titulo: s.titulo) } label: { Text("Sumar") }.tecla(chica: true).disabled(autos.count >= 20)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                    }
                }
            }
            BotonS1("Nueva rutina") {
                sumar(Automatizacion(id: nuevoId("n"), activa: true, cuando: "hora", hora: "08:00",
                                     hacer: [AccionAuto(tipo: "decir", texto: "¡Hola, {dueno}!")]), titulo: "")
            }
            .disabled(autos.count >= 20)
            .padding(.top, 24)
        }
    }

    /// El nombre que se ve: lo que dice (sin plantillas) o el cuándo.
    private func titulo(_ a: Automatizacion) -> String {
        if a.cuando == "hora", a.hora == "07:30", a.hacer.first?.texto == "{clima}. {hoy}" { return "Buen día" }
        if a.cuando == "hora", a.dias == "V", a.hacer.first?.texto == "¿Pedimos pizza?" { return "Viernes de pizza" }
        if a.hacer.contains(where: { $0.tipo == "modo" && $0.modo == "reloj" }) && a.cuando == "hora" { return "A dormir" }
        if let d = a.hacer.first(where: { $0.tipo == "decir" })?.texto, !d.isEmpty, !d.hasPrefix("{") { return d }
        return NOMBRES_CUANDO[a.cuando] ?? a.cuando
    }

    private func detalle(_ a: Automatizacion) -> String {
        var partes: [String] = []
        if a.cuando == "hora" {
            let d = a.dias ?? ""
            partes.append(d.isEmpty || d.count == 7 ? "Todos los días" : DIAS_SEMANA.filter { d.contains($0.letra) }.map(\.nombre).joined(separator: ", "))
        } else {
            partes.append(NOMBRES_CUANDO[a.cuando] ?? a.cuando)
        }
        if let t = a.hacer.first(where: { $0.tipo == "decir" })?.texto { partes.append("«\(t)»") }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder private func fila(_ i: Int) -> some View {
        let a = autos[i]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { abierta = abierta == a.id ? nil : a.id } label: {
                    HStack(spacing: 12) {
                        Text(a.cuando == "hora" ? (a.hora ?? "08:00") : "·").font(S1Tipo.seccion.monospacedDigit()).foregroundStyle(Color.s1Tinta)
                            .frame(minWidth: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titulo(a)).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                            Text(detalle(a)).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { autos[i].activa.toggle(); guardar() } label: { Interruptor(prendido: a.activa) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(titulo(a))
                    .accessibilityValue(a.activa ? "Prendida" : "Apagada")
            }
            if abierta == a.id { editor(i, a) }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
        .opacity(a.activa ? 1 : 0.6)
    }

    @ViewBuilder private func editor(_ i: Int, _ a: Automatizacion) -> some View {
        if a.cuando == "hora" {
            let hora = Binding<Date>(get: {
                let m = aMinutos(a.hora ?? "08:00")
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            }, set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                autos[i].hora = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                guardar()
            })
            DatePicker("Hora", selection: hora, displayedComponents: .hourAndMinute)
                .font(S1Tipo.cuerpoFuerte).tint(Color.s1Naranja)
            let dias = a.dias ?? "LMXJVSD"
            HStack(spacing: 4) {
                ForEach(DIAS_SEMANA, id: \.letra) { d in
                    Button { autos[i].alternarDia(d.letra); guardar() } label: { Text(d.letra) }
                        .buttonStyle(EstiloDia(prendido: dias.contains(d.letra)))
                        .accessibilityLabel(d.nombre)
                }
            }
        }
        if let j = a.hacer.firstIndex(where: { $0.tipo == "decir" }) {
            CampoAccionS1(valor: a.hacer[j].texto ?? "") { v in
                let t = cortarBytes(v.trimmingCharacters(in: .whitespaces), MAX_TEXTO)
                autos[i].hacer[j].texto = t.isEmpty ? "¡Hola!" : t
                guardar()
            }
            Flujo(espacio: 8, renglon: 8) {
                ForEach(["{clima}", "{hoy}", "{dueno}", "{hora}"], id: \.self) { p in
                    ChipS1(p) {
                        let t = cortarBytes((autos[i].hacer[j].texto ?? "") + " " + p, MAX_TEXTO)
                        autos[i].hacer[j].texto = t
                        guardar()
                    }
                }
            }
        }
        HStack {
            Button { probar(i) } label: { Text("Probar") }.tecla(chica: true)
            Spacer()
            Button { autos.remove(at: i); abierta = nil; guardar() } label: { Text("Borrar") }.tecla(chica: true)
        }
    }

    private func cargar() async {
        do {
            autos = try await api.automatizaciones(sesion.id).lista
            fallo = false
        } catch {
            fallo = true
        }
        cargando = false
    }

    private func sumar(_ a: Automatizacion, titulo: String) {
        autos.append(a)
        abierta = a.id
        guardar(ya: true)
    }

    private func guardar(ya: Bool = false) {
        reloj?.cancel()
        let id = sesion.id
        let l = autos
        reloj = Task {
            if !ya { try? await Task.sleep(for: .milliseconds(700)) }
            if Task.isCancelled { return }
            do {
                _ = try await api.guardarAutomatizaciones(id, l)
                error = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func probar(_ i: Int) {
        let id = sesion.id
        Task { try? await api.probarAutomatizacion(id, i) }
    }
}

/// El texto de una acción (se guarda al terminar de escribir).
private struct CampoAccionS1: View {
    let valor: String
    let guardar: (String) -> Void
    @State private var texto = ""

    var body: some View {
        CampoS1(ayuda: "Lo que dice", texto: $texto) { guardar(texto) }
            .onAppear { texto = valor }
            .onChange(of: texto) { _, v in let x = cortarBytes(v, MAX_TEXTO); if x != v { texto = x } }
            .onDisappear { if texto != valor { guardar(texto) } }
    }
}

// MARK: - 18 · El diario

/// Una entrada del diario (lo que pasó: cobros, rutinas, lo de ella).
private struct EntradaDiario: Identifiable {
    enum Tipo { case cobro, rutina, ella }
    let id = UUID()
    let cuando: Date
    let texto: String
    let tipo: Tipo
    let cara: String
}

/// 18 · El diario: lo que pasó, por día, con su cara de ese momento.
@MainActor
struct DiarioS1: View {
    let sesion: SesionS1
    @State private var entradas: [EntradaDiario] = []
    @State private var memoria: Memoria?
    @State private var cargando = true
    @State private var fallo = false
    @State private var filtro = 0

    private static let filtros = ["Todo", "Cobros", "Rutinas", "Ella"]

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if cargando {
            EstadoCargando(renglones: 4).task { await cargar() }
        } else if fallo {
            EstadoError(texto: "No pude leer su diario.") { Task { await cargar() } }
        } else {
            contenido
        }
    }

    private var filtradas: [EntradaDiario] {
        switch filtro {
        case 1: entradas.filter { $0.tipo == .cobro }
        case 2: entradas.filter { $0.tipo == .rutina }
        case 3: entradas.filter { $0.tipo == .ella }
        default: entradas
        }
    }

    @ViewBuilder private var contenido: some View {
        let config = sesion.modelo.config.paraDibujar
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.filtros.enumerated()), id: \.offset) { i, f in
                        ChipS1(f, elegido: filtro == i) { filtro = i }
                    }
                }
            }
            if let m = memoria {
                HStack(spacing: 8) {
                    dato("\(m.dias)", "días juntos")
                    dato("\(m.racha)", "de racha")
                    dato("\(m.caricias)", "caricias")
                }
                .padding(.top, 16)
            }
            let l = filtradas
            if l.isEmpty {
                EstadoVacio(texto: "Todavía no pasó nada.", expresion: "pensando")
            } else {
                let grupos = Dictionary(grouping: l) { Calendar.current.startOfDay(for: $0.cuando) }
                ForEach(grupos.keys.sorted(by: >), id: \.self) { dia in
                    Seccion(Self.nombreDia(dia), arriba: 24)
                    VStack(spacing: 0) {
                        ForEach((grupos[dia] ?? []).sorted { $0.cuando > $1.cuando }) { e in
                            FilaS1(titulo: e.texto, detalle: TePagaronS1.hora.string(from: e.cuando)) {
                                MarcoPantalla(tamano: .lista) { CaraDibujada(expresion: e.cara, config: config, fps: 4) }
                            }
                        }
                    }
                }
            }
            if let m = memoria, !m.hitos.isEmpty {
                Seccion("Lo que lograron")
                Flujo(espacio: 8, renglon: 8) {
                    ForEach(m.hitos, id: \.self) { h in ChipS1(NOMBRES_HITO[h] ?? h) {} }
                }
            }
        }
    }

    private func dato(_ n: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(S1Tipo.dato).foregroundStyle(Color.s1Tinta)
            Text(t).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.s1Superficie))
    }

    static func nombreDia(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoy" }
        if cal.isDateInYesterday(d) { return "Ayer" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "EEEE d"
        return f.string(from: d).capitalized
    }

    private func cargar() async {
        let api = Cuenta.compartida.api
        let id = sesion.id
        var l: [EntradaDiario] = []
        var algo = false
        await sesion.cobros.cargar()
        if sesion.cobros.fase == .lista {
            algo = true
            for c in sesion.cobros.lista {
                if let p = c.pagado {
                    let de = c.pagador.isEmpty ? c.quien : c.pagador
                    l.append(EntradaDiario(cuando: p, texto: "Te pagaron \(pesos(c.monto))" + (de.isEmpty ? "" : " · \(de)"), tipo: .cobro, cara: "emocionado"))
                }
                if let cr = c.creado {
                    l.append(EntradaDiario(cuando: cr, texto: "Cobro de \(pesos(c.monto))" + (c.quien.isEmpty ? "" : " a \(c.quien)"), tipo: .cobro, cara: "contento"))
                }
            }
        }
        if let r = try? await api.automatizaciones(id) {
            algo = true
            for h in r.historial {
                guard let en = h.en else { continue }
                l.append(EntradaDiario(cuando: en, texto: "\(NOMBRES_CUANDO[h.evento] ?? h.evento): \(h.accion)", tipo: .rutina, cara: h.ok ? "contento" : "sorpresa"))
            }
        }
        if let r = try? await api.resumen(id) {
            algo = true
            let hoy = Date()
            if r.juegos > 0 {
                l.append(EntradaDiario(cuando: hoy, texto: "Jugaron \(r.juegos) \(r.juegos == 1 ? "vez" : "veces") · ganó \(r.ganados)", tipo: .ella, cara: "risa"))
            }
            if r.suenos > 0 {
                let con = r.sonoCon.isEmpty ? "" : " con \(r.sonoCon.joined(separator: ", "))"
                l.append(EntradaDiario(cuando: Calendar.current.startOfDay(for: hoy).addingTimeInterval(3 * 3600), texto: "Soñó\(con)", tipo: .ella, cara: "dormido"))
            }
            if !r.espero.isEmpty { l.append(EntradaDiario(cuando: hoy, texto: "Te esperó a las \(r.espero)", tipo: .ella, cara: "enamorado")) }
            if let a = r.animo {
                let t = ["bien": "Le dijiste que estabas bien", "medio": "Le dijiste que más o menos", "mal": "Le dijiste que mal"][a] ?? "Le contaste cómo estabas"
                l.append(EntradaDiario(cuando: hoy, texto: t, tipo: .ella, cara: a == "mal" ? "triste" : "contento"))
            }
        }
        if let m = try? await api.memoria(id) { memoria = m.memoria; algo = true }
        entradas = l
        fallo = !algo
        cargando = false
    }
}

// MARK: - 25 · Memoria

/// 25 · Memoria: lo que le contaste y no se olvida ("N cosas"), con Olvidar y
/// "Contale algo".
@MainActor
struct MemoriaS1: View {
    let sesion: SesionS1
    @State private var lista: [Recuerdo] = []
    @State private var max = 30
    @State private var cargando = true
    @State private var fallo = false
    @State private var nuevo = ""
    @State private var error = ""

    private var api: ApiSintetica { Cuenta.compartida.api }

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if cargando {
            EstadoCargando(renglones: 4).task { await cargar() }
        } else if fallo {
            EstadoError(texto: "No pude ver su memoria.") { Task { await cargar() } }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(lista.count) \(lista.count == 1 ? "cosa" : "cosas")").font(.system(size: 44, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.s1Tinta)
                Text("de \(max)").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
                HStack(spacing: 8) {
                    CampoS1(ayuda: "Mi cumple es el 3 de mayo", texto: $nuevo) { sumar() }
                    Button { sumar() } label: { IconoS1(.sumar, tamano: 20) }.tecla(cuadrada: true)
                        .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty || lista.count >= max)
                        .accessibilityLabel("Contale algo")
                }
                .padding(.top, 16)
                if !error.isEmpty { EstadoError(texto: "No se guardó.") { sumar() } }
                if lista.isEmpty {
                    EstadoVacio(texto: "Contale algo.", expresion: "pensando")
                } else {
                    Seccion("Lo que sabe")
                    VStack(spacing: 0) {
                        ForEach(lista.reversed()) { r in
                            HStack(spacing: 12) {
                                Text(r.texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button { sacar(r) } label: { Text("Olvidar") }.tecla(chica: true)
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }

    private func cargar() async {
        do { (lista, max) = try await api.recuerdos(); fallo = false } catch { fallo = true }
        cargando = false
    }

    private func sumar() {
        let t = String(nuevo.trimmingCharacters(in: .whitespaces).prefix(120))
        guard !t.isEmpty else { return }
        Task {
            do { (lista, max) = try await api.sumarRecuerdo(t); nuevo = ""; error = "" } catch { self.error = error.localizedDescription }
        }
    }

    private func sacar(_ r: Recuerdo) {
        Task {
            do { (lista, max) = try await api.sacarRecuerdo(r.clave) } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - 26 · Agenda

/// 26 · Agenda: la semana en días (el elegido en tinta invertida), lo de ese
/// día, lo de la semana que viene y, abajo, tu calendario.
@MainActor
struct AgendaS1: View {
    let sesion: SesionS1
    @State private var agenda: Agenda?
    @State private var cargando = true
    @State private var fallo = false
    @State private var dia = 0

    private var dias: [Date] {
        let hoy = Calendar.current.startOfDay(for: Date())
        return (0 ..< 7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: hoy) }
    }

    var body: some View {
        if !sesion.modelo.esNube {
            SoloNube()
        } else if cargando {
            EstadoCargando(renglones: 3).task { await cargar() }
        } else if fallo {
            EstadoError(texto: "No pude ver tu agenda.") { Task { await cargar() } }
        } else {
            contenido
        }
    }

    private func eventos(_ d: Date) -> [EventoAgenda] {
        (agenda?.proximos ?? []).filter { e in e.inicio.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false }
    }

    @ViewBuilder private var contenido: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agenda?.conectada == true {
                HStack(spacing: 4) {
                    ForEach(Array(dias.enumerated()), id: \.offset) { i, d in
                        let si = i == dia
                        Button { dia = i } label: {
                            VStack(spacing: 2) {
                                Text(Self.corto(d)).font(S1Tipo.caption)
                                Text("\(Calendar.current.component(.day, from: d))").font(S1Tipo.cuerpoFuerte.monospacedDigit())
                            }
                            .foregroundStyle(si ? Color.s1InvTexto : Color.s1Tinta)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(si ? Color.s1Inv : Color.clear))
                            .overlay(alignment: .bottom) {
                                if !eventos(d).isEmpty && !si { Circle().fill(Color.s1Naranja).frame(width: 5, height: 5).padding(.bottom, 4) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(si ? [.isSelected] : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: dia)
                let l = dia < dias.count ? eventos(dias[dia]) : []
                if l.isEmpty {
                    EstadoVacio(texto: "Nada ese día.", expresion: "contento")
                } else {
                    VStack(spacing: 0) {
                        ForEach(l) { e in
                            FilaS1(titulo: e.titulo, detalle: e.todoElDia ? "Todo el día" : "", valor: e.todoElDia ? "" : e.inicio.map { TePagaronS1.hora.string(from: $0) } ?? "") {
                                IconoEnCirculo(icono: .recordar)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
                let despues = (agenda?.proximos ?? []).filter { e in (e.inicio ?? .distantPast) >= (dias.last ?? Date()).addingTimeInterval(86400) }
                if !despues.isEmpty {
                    Seccion("La semana que viene")
                    VStack(spacing: 0) {
                        ForEach(despues.prefix(6)) { e in
                            FilaS1(titulo: e.titulo, detalle: e.inicio.map { DiarioS1.nombreDia($0) } ?? "",
                                   valor: e.todoElDia ? "" : e.inicio.map { TePagaronS1.hora.string(from: $0) } ?? "") { EmptyView() }
                        }
                    }
                }
                Seccion("Tu calendario")
            } else {
                EstadoVacio(texto: "Conectá tu calendario.", expresion: "pensando")
            }
            ModAgenda(modelo: sesion.modelo)
        }
    }

    static func corto(_ d: Date) -> String {
        let w = Calendar.current.component(.weekday, from: d)
        return ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"][max(0, min(6, w - 1))]
    }

    private func cargar() async {
        do { agenda = try await Cuenta.compartida.api.agenda(); fallo = false } catch { fallo = true }
        cargando = false
    }
}

// MARK: - 27 · Hábitos

/// 27 · Hábitos: su pantalla grande festejando, la racha más larga en grande,
/// la semana en puntitos y, abajo, cada hábito.
@MainActor
struct HabitosS1: View {
    let sesion: SesionS1
    @State private var vistas: [VistaHabito] = []

    var body: some View {
        let modelo = sesion.modelo
        let mejor = vistas.max { $0.racha < $1.racha }
        let semana = ultimosDias(7)
        VStack(alignment: .leading, spacing: 0) {
            PantallaGrande {
                CaraDibujada(expresion: (mejor?.racha ?? 0) >= 3 ? "emocionado" : "contento", config: modelo.config.paraDibujar, pantalla: modelo.pantalla)
            }
            if let m = mejor, m.racha > 0 {
                Text("\(m.racha) \(m.racha == 1 ? "día" : "días")").font(.system(size: 44, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.s1Tinta).frame(maxWidth: .infinity).padding(.top, 16)
                Text("\(m.nombre), sin faltar.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2).frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    ForEach(Array(semana.enumerated()), id: \.offset) { _, d in
                        let hecho = m.dias.contains(d)
                        VStack(spacing: 4) {
                            Circle().fill(hecho ? Color.s1Inv : Color.clear)
                                .overlay(Circle().strokeBorder(hecho ? Color.s1Inv : Color.s1Linea, lineWidth: 2))
                                .frame(width: 24, height: 24)
                            Text(IAGastoS1.letra(d)).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 16)
            } else if modelo.config.habitos.isEmpty {
                EstadoVacio(texto: "Sumá un hábito.", expresion: "contento")
            }
            Seccion("Tus hábitos")
            ModHabitos(modelo: modelo)
        }
        .task(id: modelo.versionConfig) {
            guard modelo.esNube else { return }
            if let v = try? await Cuenta.compartida.api.habitos(modelo.id) { vistas = v }
        }
    }
}
