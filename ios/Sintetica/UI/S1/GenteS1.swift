import SwiftUI

// 29 · Avisos del celu, 30 · Cuidado y 31 · Chicos.

/// 30 · Cuidado: la pastilla (con "Ya la tomó"), el «¿cómo estás?» de cada
/// día, los horarios que aprendió y avisar a la familia si no aparece.
@MainActor
struct CuidadoS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var horarios: Horarios?
    @State private var resumen: ResumenDia?
    @State private var vistas: [VistaHabito] = []
    @State private var aviso = ""

    private var indicePastilla: Int? { sesion.modelo.config.recordatorios.firstIndex { $0.texto.lowercased().contains("pastilla") } }
    private var habitoPastilla: Int? { sesion.modelo.config.habitos.firstIndex { $0.icono == "pastilla" } }

    var body: some View {
        let modelo = sesion.modelo
        let c = modelo.config
        let cu = c.cuidado
        VStack(alignment: .leading, spacing: 0) {
            if let i = indicePastilla {
                let r = c.recordatorios[i]
                let hecha = habitoPastilla.flatMap { h in vistas.first { $0.indice == h } }?.hoy ?? false
                TarjetaS1 {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.texto).font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta).lineLimit(2)
                            Text(r.hora).font(S1Tipo.dato).foregroundStyle(Color.s1Tinta)
                        }
                        Spacer()
                        MarcoPantalla(tamano: .lista) { PantallaPastilla(hora: r.hora) }
                    }
                    Text(cu.resumen ? "Si no la toma, le avisa a la familia." : "La familia no se entera.")
                        .font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                    if habitoPastilla == nil {
                        BotonS1("Llevar la cuenta") {
                            let h = r.hora
                            modelo.cambiar { $0.habitos = $0.habitos + [Habito(nombre: "Pastilla", icono: "pastilla", hora: h)] }
                        }
                        .disabled(c.habitos.count >= MAX_HABITOS)
                    } else {
                        BotonS1(hecha ? "Tomada" : "Ya la tomó", naranja: !hecha) { tomo() }.disabled(hecha)
                    }
                    HStack {
                        Spacer()
                        Button { ir(.modulo(.recordatorios)) } label: { Text("Cambiar la hora") }.tecla(chica: true)
                    }
                }
            } else {
                TarjetaS1 {
                    Text("La pastilla").font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
                    BotonS1("Sumar la pastilla") { sumarPastilla() }
                        .disabled(c.recordatorios.count >= MAX_RECORDATORIOS)
                }
            }
            if !aviso.isEmpty { AvisoConsola(texto: aviso).padding(.top, 12) }
            Seccion("«¿Cómo estás?»")
            HStack(spacing: 12) {
                MarcoPantalla(tamano: .lista) { CaraDibujada(expresion: resumen?.animo == "mal" ? "triste" : "contento", config: c.paraDibujar, fps: 4) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Todos los días").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                    Text(textoAnimo).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                }
                Spacer()
                Button { modelo.cambiar { $0.cambiarCuidado { $0.animo.toggle() } } } label: { Interruptor(prendido: cu.animo) }
                    .buttonStyle(.plain).accessibilityLabel("¿Cómo estás?").accessibilityValue(cu.animo ? "Prendido" : "Apagado")
            }
            Seccion("Horarios que aprendió")
            if let h = horarios, h.dias > 0 {
                VStack(spacing: 0) {
                    FilaS1(titulo: "Sale", valor: h.salis.isEmpty ? "—" : h.salis) { IconoEnCirculo(icono: .sistema("figure.walk")) }
                    FilaS1(titulo: "Llega", valor: h.llegas.isEmpty ? "—" : h.llegas) { IconoEnCirculo(icono: .sistema("house")) }
                    FilaS1(titulo: "Duerme", valor: h.dormis.isEmpty ? "—" : h.dormis) { IconoEnCirculo(icono: .sistema("moon")) }
                }
            } else if horarios == nil && modelo.esNube {
                EstadoCargando(renglones: 2)
            } else {
                Text("Todavía aprendiendo.").font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta2)
            }
            Seccion("Avisos a la familia")
            VStack(spacing: 0) {
                FilaToggle(titulo: "Avisar si no aparece", detalle: "Después de \(cu.extranarDias) \(cu.extranarDias == 1 ? "día" : "días")", prendido: cu.extranar) {
                    modelo.cambiar { $0.cambiarCuidado { $0.extranar.toggle() } }
                }
                if cu.extranar {
                    FilaPasos(titulo: "Días", valor: "\(cu.extranarDias)", puedeMenos: cu.extranarDias > 1, puedeMas: cu.extranarDias < 7,
                              menos: { modelo.cambiar { $0.cambiarCuidado { $0.extranarDias = max(1, $0.extranarDias - 1) } } },
                              mas: { modelo.cambiar { $0.cambiarCuidado { $0.extranarDias = min(7, $0.extranarDias + 1) } } })
                }
                FilaToggle(titulo: "El resumen del día", detalle: "Por Telegram", prendido: cu.resumen) {
                    modelo.cambiar { $0.cambiarCuidado { $0.resumen.toggle() } }
                }
            }
            Button { ir(.modulo(.amigos)) } label: {
                FilaS1(titulo: "Sumar a alguien", flecha: true) { IconoEnCirculo(icono: .sistema("person.badge.plus")) }
            }
            .buttonStyle(.plain)
            Seccion("Agua y pausas")
            ModCuidado(modelo: modelo)
        }
        .task {
            guard sesion.modelo.esNube else { return }
            let api = Cuenta.compartida.api
            horarios = (try? await api.horarios(sesion.id)) ?? Horarios([:])
            resumen = try? await api.resumen(sesion.id)
            vistas = (try? await api.habitos(sesion.id)) ?? []
        }
    }

    private var textoAnimo: String {
        switch resumen?.animo {
        case "bien": "Hoy: «Bien»."
        case "medio": "Hoy: «Más o menos»."
        case "mal": "Hoy: «Mal»."
        default: "Hoy todavía no contestó."
        }
    }

    private func sumarPastilla() {
        sesion.modelo.cambiar { c in
            c.recordatorios = c.recordatorios + [Recordatorio(hora: "21:00", texto: "La pastilla")]
            if !c.habitos.contains(where: { $0.icono == "pastilla" }), c.habitos.count < MAX_HABITOS {
                c.habitos = c.habitos + [Habito(nombre: "Pastilla", icono: "pastilla", hora: "21:00")]
            }
        }
    }

    private func tomo() {
        guard let h = habitoPastilla else { return }
        Task {
            do {
                let v = try await Cuenta.compartida.api.marcarHabito(sesion.id, h, hecho: true)
                if let k = vistas.firstIndex(where: { $0.indice == h }) { vistas[k] = v } else { vistas.append(v) }
                aviso = "Anotado."
            } catch {
                aviso = "No pude anotarlo."
            }
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

/// 31 · Chicos: la hora de dormir, los cuentos, los juegos y el control de
/// los padres. La principal: "Contale un cuento".
@MainActor
struct ChicosS1: View {
    let sesion: SesionS1
    let ir: (IrA) -> Void
    @State private var aviso = ""
    @State private var tope: Int?

    private static let cuentos: [(titulo: String, minutos: Int)] = [("El dragón con hipo", 6), ("La yerba que quería volar", 8)]

    var body: some View {
        let modelo = sesion.modelo
        let c = modelo.config
        let cu = c.cuidado
        VStack(alignment: .leading, spacing: 0) {
            TarjetaS1 {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("La hora de dormir").font(S1Tipo.seccion).foregroundStyle(Color.s1Tinta)
                        Text(c.duerme).font(S1Tipo.dato).foregroundStyle(Color.s1Tinta)
                    }
                    Spacer()
                    MarcoPantalla(tamano: .lista) { CaraDibujada(expresion: "dormido", config: c.paraDibujar, fps: 4) }
                }
                Text("Cuenta un cuento y se duerme con vos.").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                HStack(spacing: 8) {
                    BotonS1("−15 min", naranja: false) { modelo.cambiar { $0.moverHorario(despierta: false, minutos: -15) } }
                    BotonS1("+15 min", naranja: false) { modelo.cambiar { $0.moverHorario(despierta: false, minutos: 15) } }
                }
            }
            Seccion("Cuentos")
            VStack(spacing: 0) {
                ForEach(Self.cuentos, id: \.titulo) { k in
                    HStack(spacing: 12) {
                        IconoEnCirculo(icono: .sistema("book"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.titulo).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta).lineLimit(1)
                            Text("\(k.minutos) minutos").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                        }
                        Spacer(minLength: 8)
                        Button { pedir("Contame el cuento «\(k.titulo)»", "Lo está contando.") } label: { Text("Contar") }.tecla(chica: true)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                }
                HStack(spacing: 12) {
                    IconoEnCirculo(icono: .sistema("sparkles"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inventar uno juntos").font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                        Text("Lo arman entre los dos").font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                    }
                    Spacer(minLength: 8)
                    Button { pedir("Inventemos un cuento juntos", "Empezó el cuento.") } label: { Text("Empezar") }.tecla(chica: true)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
            }
            if let r = sesion.hilo.last, !r.deMi, !aviso.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    MarcoPantalla(tamano: .charla) { CaraDibujada(expresion: nombreDibujable(r.expresion), config: c.paraDibujar, fps: 6) }
                    Text(r.texto).font(S1Tipo.cuerpo).foregroundStyle(Color.s1Tinta).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            } else if sesion.pensando {
                PuntitosPensando().padding(.top, 12)
            }
            Seccion("Juegos")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                TeclaAtajo(icono: .sistema("scissors"), nombre: "Piedra, papel o tijera") { jugar("ppt") }
                TeclaAtajo(icono: .sistema("die.face.5"), nombre: "Dado") { jugar("dado") }
                TeclaAtajo(icono: .sistema("circle.circle"), nombre: "Moneda") { jugar("moneda") }
                TeclaAtajo(icono: .sistema("pawprint"), nombre: "Adiviná el animal") { pedir("Juguemos a adivinar el animal", "¡A jugar!") }
            }
            .disabled(!modelo.conectado)
            if !aviso.isEmpty, sesion.hilo.last?.deMi != false { AvisoConsola(texto: aviso).padding(.top, 12) }
            Seccion("Control de los padres")
            VStack(spacing: 0) {
                FilaToggle(titulo: "Habla sola", detalle: "Si está apagado, solo contesta", prendido: c.frecuenciaHabla > 0.05) {
                    let v = c.frecuenciaHabla > 0.05 ? 0.0 : 0.5
                    modelo.cambiar { $0.ponerFrecuenciaHabla(v) }
                }
                FilaToggle(titulo: "Sin frases de apego", detalle: "No dice que te extraña", prendido: !cu.extranar) {
                    modelo.cambiar { $0.cambiarCuidado { $0.extranar.toggle() } }
                }
                FilaToggle(titulo: "Le pregunta cómo está", prendido: cu.animo) { modelo.cambiar { $0.cambiarCuidado { $0.animo.toggle() } } }
                Button { ir(.modulo(.iaGasto)) } label: {
                    FilaS1(titulo: "Tiempo de charla", valor: tope.map { $0 > 0 ? "\($0) por día" : "Sin tope" } ?? "—", flecha: true) { EmptyView() }
                }
                .buttonStyle(.plain)
                Button { ir(.modulo(.amigos)) } label: {
                    FilaS1(titulo: "Amigos", detalle: "Solo los que vos aprobás", flecha: true) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
            BotonS1("Contale un cuento") { pedir("Contame un cuento", "Lo está contando.") }
                .disabled(sesion.pensando)
                .padding(.top, 24)
        }
        .task {
            guard modelo.esNube else { return }
            tope = (try? await Cuenta.compartida.api.iaPropia())?.tope
        }
    }

    private func pedir(_ t: String, _ a: String) {
        aviso = a
        Task {
            await sesion.enviar(t)
            try? await Task.sleep(for: .seconds(20))
            aviso = ""
        }
    }

    private func jugar(_ j: String) {
        Task {
            aviso = await sesion.modelo.jugar(j) ?? "¡A jugar!"
            try? await Task.sleep(for: .seconds(2.5))
            aviso = ""
        }
    }
}

/// 29 · Avisos del celu: qué apps y llamadas le cuentan (toggles), cuándo se
/// calla y, abajo, los avisos a medida.
@MainActor
struct AvisosCeluS1: View {
    let sesion: SesionS1

    private static let apps: [(nombre: String, detalle: String, tipo: String, logo: String?, simbolo: String, cara: String)] = [
        ("WhatsApp", "Te dice quién escribió", "notificacion", nil, "bubble.left", "sorpresa"),
        ("Mercado Pago", "Cuando te pagan", "notificacion", "logo-mercadopago", "", "emocionado"),
        ("Calendario", "Antes de cada turno", "notificacion", "logo-googlecalendar", "", "curioso"),
        ("Llamadas", "Te dice quién llama", "llamada", nil, "phone", "sorpresa"),
        ("Mail", "Los nuevos", "notificacion", "logo-mail", "", "curioso"),
    ]

    var body: some View {
        let modelo = sesion.modelo
        let c = modelo.config
        let l = c.avisos
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Self.apps, id: \.nombre) { a in
                    let prendido = l.contains { esDe($0, a.nombre, a.tipo) }
                    Button { alternar(a.nombre, a.tipo, a.cara, prendido) } label: {
                        HStack(spacing: 12) {
                            if let logo = a.logo {
                                FichaLogo(imagen: logo)
                            } else {
                                IconoEnCirculo(icono: .sistema(a.simbolo))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.nombre).font(S1Tipo.cuerpoFuerte).foregroundStyle(Color.s1Tinta)
                                Text(a.detalle).font(S1Tipo.caption).foregroundStyle(Color.s1Tinta2)
                            }
                            Spacer(minLength: 8)
                            Interruptor(prendido: prendido)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.s1Linea).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!prendido && l.count >= MAX_AVISOS)
                    .accessibilityValue(prendido ? "Prendido" : "Apagado")
                }
            }
            Seccion("Silencio")
            VStack(spacing: 0) {
                FilaS1(titulo: "De \(c.duerme) a \(c.despierta)", detalle: "Mientras duerme, no avisa") { IconoEnCirculo(icono: .sistema("moon")) }
            }
            Seccion("A medida")
            AvisosDelCelu(modelo: modelo)
        }
    }

    private func esDe(_ a: AvisoCelu, _ nombre: String, _ tipo: String) -> Bool {
        tipo == "llamada" ? (a.tipo == "llamada" && a.app.isEmpty && a.contacto.isEmpty) : (a.tipo == tipo && a.app.lowercased() == nombre.lowercased())
    }

    private func alternar(_ nombre: String, _ tipo: String, _ cara: String, _ prendido: Bool) {
        sesion.modelo.cambiar { c in
            if prendido {
                c.avisos = c.avisos.filter { !esDe($0, nombre, tipo) }
            } else if c.avisos.count < MAX_AVISOS {
                var a = AvisoCelu(tipo: tipo, expresion: cara, decir: tipo == "llamada" ? "Te llama {contacto}" : "{app}")
                if tipo != "llamada" { a.app = nombre }
                c.avisos = c.avisos + [a]
            }
        }
    }
}
