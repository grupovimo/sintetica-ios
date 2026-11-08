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

    /// Vuelve a Mis robots.
    static func alInicio(_ ruta: inout [Ruta]) { ruta.removeAll() }
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
