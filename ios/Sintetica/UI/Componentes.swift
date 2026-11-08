import SwiftUI

/// El único botón naranja de cada pantalla (manual: un solo primario por pantalla).
struct BotonPrimario: View {
    let texto: String
    var habilitado = true
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto.uppercased()).font(Tipos.boton).tracking(1).frame(maxWidth: .infinity).frame(height: 52)
                .foregroundStyle(habilitado ? Color.sobreNaranja : Color.tintaSuave)
                .background(habilitado ? Color.naranja : Color.linea, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!habilitado)
    }
}

struct BotonSecundario: View {
    let texto: String
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto.uppercased()).font(Tipos.boton).tracking(1).frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(Color.tinta)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.linea, lineWidth: 1))
        }
    }
}

struct Etiqueta: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View { Text(texto.uppercased()).font(Tipos.etiqueta).tracking(1.3).foregroundStyle(Color.tintaSuave) }
}

/// Una fila de datos en mono, separada por una línea fina.
struct FilaDato: View {
    let etiqueta: String
    let valor: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Etiqueta(etiqueta)
                Spacer()
                Text(valor).font(Tipos.dato).foregroundStyle(Color.tinta)
            }
            .padding(.vertical, 12)
            Rectangle().fill(Color.linea).frame(height: 1)
        }
    }
}

struct Seccion<Contenido: View>: View {
    let titulo: String
    @ViewBuilder let contenido: Contenido
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titulo).font(Tipos.titulo).foregroundStyle(Color.tinta)
            contenido
        }
    }
}

struct Aviso: View {
    let texto: String
    var body: some View {
        Text(texto).font(Tipos.chico).foregroundStyle(Color.tinta).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color.naranjaClaro, in: RoundedRectangle(cornerRadius: 12))
    }
}
