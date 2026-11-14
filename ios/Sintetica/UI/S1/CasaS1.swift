import SwiftUI

/// Adónde lleva un toque desde las tabs.
enum IrA {
    case modulo(Modulo)
    case laboratorio(LaboratorioVista.Rack)
    case cerca
    case misS1
    case cuenta
    /// A la Charla, con algo ya escrito (vacío: solo abre el teclado).
    case charla(String)
    /// Le dice algo ya (los "de un toque") y muestra la Charla.
    case charlar(String)
    case pestana(PestanaS1)
}

/// La raíz: la S1 elegida con sus tabs; sin ninguna, Mis S1.
@MainActor
struct RaizS1: View {
    @Binding var ruta: [Ruta]
    private var eleccion = EleccionS1.compartida
    @State private var sesion: SesionS1?

    init(ruta: Binding<[Ruta]>) { _ruta = ruta }

    var body: some View {
        Group {
            if let s = sesion {
                CasaS1(ruta: $ruta, sesion: s).id(s.id)
            } else {
                MisS1(ruta: $ruta, esRaiz: true)
            }
        }
        .onAppear(perform: sincronizar)
        .onChange(of: eleccion.id) { _, _ in sincronizar() }
    }

    private func sincronizar() {
        guard sesion?.id != eleccion.id else { return }
        sesion?.cerrar()
        sesion = eleccion.id.map { SesionS1(id: $0) }
    }
}

/// La S1 abierta: Inicio, Charla, Hoy y Más, con la tab bar abajo. Cada
/// módulo se abre encima (header + atrás).
@MainActor
struct CasaS1: View {
    @Binding var ruta: [Ruta]
    let sesion: SesionS1
    @State private var pestana: PestanaS1 = .inicio
    @State private var abierto: Modulo?
    @State private var laboratorio = false
    @State private var rackLab: LaboratorioVista.Rack = .expresiones
    @State private var encender = false
    @State private var cerca = false
    @State private var borrador = ""
    @State private var enfocarCharla = false

    var body: some View {
        let modelo = sesion.modelo
        VStack(spacing: 0) {
            Group {
                switch pestana {
                case .inicio: InicioS1(sesion: sesion, ir: ir)
                case .charla: CharlaS1(sesion: sesion, borrador: $borrador, enfocar: $enfocarCharla)
                case .hoy: HoyS1(sesion: sesion, ir: ir)
                case .mas: MasS1(sesion: sesion, ir: ir)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBarS1(actual: $pestana, nombre: sesion.nombre)
        }
        .background(FondoConsola())
        .overlay(alignment: .top) { avisoArriba }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: modelo.aviso)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $abierto) { m in
            DetalleModulo(ruta: $ruta, sesion: sesion, modulo: m)
        }
        .task {
            await sesion.abrir()
            mirarEncender()
        }
        .onChange(of: modelo.fase) { _, _ in mirarEncender() }
        .fullScreenCover(isPresented: $laboratorio) { LaboratorioVista(modelo: modelo, rack: rackLab) }
        .fullScreenCover(isPresented: $encender) { EncenderVista(modelo: modelo) }
        .sheet(isPresented: $cerca) { CercaVista(modelo: modelo) }
    }

    @ViewBuilder private var avisoArriba: some View {
        let modelo = sesion.modelo
        if let a = modelo.aviso {
            AvisoDelRobot(aviso: a, sesion: sesion,
                          alarma: a.despertador && modelo.conectado ? { accion in alarma(accion) } : nil) { modelo.aviso = nil }
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    private func alarma(_ accion: String) {
        Task {
            if await sesion.modelo.alarma(accion) == nil { sesion.modelo.aviso = nil }
        }
    }

    private func mirarEncender() {
        if sesion.modelo.fase == .lista, sesion.modelo.debeEncender { encender = true }
    }

    private func ir(_ a: IrA) {
        switch a {
        case let .modulo(m): abierto = m
        case let .laboratorio(r): rackLab = r; laboratorio = true
        case .cerca: cerca = true
        case .misS1: ruta.append(.misS1)
        case .cuenta: ruta.append(.cuenta)
        case let .charla(t):
            borrador = t
            enfocarCharla = true
            pestana = .charla
        case let .charlar(t):
            pestana = .charla
            Task { await sesion.enviar(t) }
        case let .pestana(p): pestana = p
        }
    }
}

/// Un módulo en su pantalla: el header con su nombre, atrás y la S1 de 72;
/// abajo el módulo, que se guarda solo.
@MainActor
struct DetalleModulo: View {
    @Binding var ruta: [Ruta]
    let sesion: SesionS1
    let modulo: Modulo
    @Environment(\.dismiss) private var cerrar
    @State private var laboratorio = false
    @State private var rackLab: LaboratorioVista.Rack = .expresiones
    @State private var cerca = false

    var body: some View {
        let modelo = sesion.modelo
        VStack(spacing: 0) {
            HeaderS1(titulo: modulo.nombre, sesion: sesion, atras: { cerrar() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if modelo.guardado == .error, !modelo.errorGuardado.isEmpty {
                        AvisoConsola(texto: modelo.errorGuardado, error: true)
                    }
                    contenido
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FondoConsola())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $laboratorio) { LaboratorioVista(modelo: modelo, rack: rackLab) }
        .sheet(isPresented: $cerca) { CercaVista(modelo: modelo) }
    }

    @ViewBuilder private var contenido: some View {
        let modelo = sesion.modelo
        switch modulo {
        case .listas: ModListas(sesion: sesion)
        case .recordatorios: ModRecordatorios(modelo: modelo)
        case .agenda: ModAgenda(modelo: modelo)
        case .habitos: ModHabitos(modelo: modelo)
        case .dia: ModDia(modelo: modelo)
        case .jugar: ModJugar(modelo: modelo)
        case .cara: ModCara(modelo: modelo)
        case .imagenes: ModImagenes(modelo: modelo)
        case .modos: ModModos(modelo: modelo)
        case .caracter: ModCaracter(modelo: modelo)
        case .habla: ModHabla(modelo: modelo)
        case .voz: ModVoz(modelo: modelo)
        case .memoria: ModMemoria(modelo: modelo)
        case .integraciones:
            ModIntegraciones(modelo: modelo)
            ModAvisos(modelo: modelo)
        case .reflejos: ModReflejos(modelo: modelo)
        case .amigos: ModAmigos(modelo: modelo)
        case .cuidado: ModCuidado(modelo: modelo)
        case .avisos: ModAvisos(modelo: modelo)
        case .ajustes:
            ModAjustes(modelo: modelo, laboratorio: { r in rackLab = r; laboratorio = true }, cerca: { cerca = true }, volver: {
                EleccionS1.compartida.elegir(nil)
                Navegacion.alInicio(&ruta)
                cerrar()
            })
        }
    }
}
