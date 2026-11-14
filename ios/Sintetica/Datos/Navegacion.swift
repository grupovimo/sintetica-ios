import SwiftUI
import UIKit

/// Cómo se vuelve en la pila de pantallas: una atrás o al inicio.
enum Navegacion {
    /// Saca la última pantalla (pop). Devuelve si había algo para sacar.
    @discardableResult
    static func volver(_ ruta: inout [Ruta]) -> Bool {
        guard !ruta.isEmpty else { return false }
        ruta.removeLast()
        return true
    }

    /// Vuelve al Inicio (la raíz).
    static func alInicio(_ ruta: inout [Ruta]) { ruta.removeAll() }

    /// Elige esta S1 y vuelve al Inicio con ella.
    @MainActor
    static func abrir(_ id: String, _ ruta: inout [Ruta]) {
        EleccionS1.compartida.elegir(id)
        ruta.removeAll()
    }
}

/// Las pantallas esconden la barra de navegación (tienen su propia tecla para
/// volver): esto devuelve el gesto de deslizar desde el borde.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
