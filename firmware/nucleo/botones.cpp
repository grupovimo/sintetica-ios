// Los botones del cubito (13/11): VOL+ es "sí" y VOL− es "no / después",
// según lo que se ve. Las pistas de abajo ("+ Apagar", "− 10 min") dicen qué
// hace cada uno; la vista siguiente (la hora grande, el clima) y la barrita
// del volumen también viven acá.
#include "fuentes.h"
#include "sistema.h"
#include "texto.h"

namespace sintetica {

bool Sistema::botonSi() {
  const uint32_t ahora = hal_.ahoraMs();
  actividad();
  if (alarma_) {
    apagarAlarma();
    return true;
  }
  if (timerSonando_ >= 0) {
    timerSonando_ = -1;
    return true;
  }
  if (recVisible_ >= 0) {
    if (recConfirmar_ == recVisible_) confirmarRecordatorio();
    cerrarRecordatorio();
    motor_.interaccion(ahora);
    hablar(Situacion::RecordatorioHecho);
    return true;
  }
  if (preguntando_) {
    responderAnimo(0);
    return true;
  }
  if (habPregunta_ >= 0) {
    marcarHabito(habPregunta_, 0, true);
    return true;
  }
  if (toqueHasta_) {
    devolverToque(ahora);
    return true;
  }
  return false;
}

bool Sistema::botonNo() {
  const uint32_t ahora = hal_.ahoraMs();
  actividad();
  if (alarma_) {
    posponerAlarma();
    return true;
  }
  if (timerSonando_ >= 0) {
    timerSonando_ = -1;
    return true;
  }
  if (recVisible_ >= 0) {  // después: si espera confirmación, insiste solo en 5 min
    cerrarRecordatorio();
    motor_.interaccion(ahora);
    return true;
  }
  if (preguntando_) {
    responderAnimo(1);
    return true;
  }
  if (habPregunta_ >= 0) {
    todaviaNo(ahora);
    return true;
  }
  if (tarjetaVisible()) {
    tarjetaHasta_ = ahora;
    return true;
  }
  if (globo_ || hablandoEnVozAlta()) {  // callate
    globoHasta_ = ahora;
    hayPendiente_ = false;
    voz_.parar();
    return true;
  }
  // Nada que contestar: la vista siguiente (la hora grande, el clima si lo
  // sabe, y de vuelta la cara).
  const bool vigente = vistaHasta_ && static_cast<int32_t>(ahora - vistaHasta_) < 0;
  uint8_t v = vigente ? static_cast<uint8_t>(vistaBoton_ + 1) : 1;
  if (v == 2 && !climaVigente()) v = 3;
  if (v >= 3) {
    vistaBoton_ = 0, vistaHasta_ = 0;
  } else {
    vistaBoton_ = v, vistaHasta_ = ahora + tiemposPanel::VISTA_MS;
  }
  motor_.interaccion(ahora);
  return true;
}

void Sistema::cambiarVolumen(int pasos) {
  actividad();
  const int v = config_.voz.volumen + pasos * 10;
  config_.voz.volumen = static_cast<uint8_t>(v < 10 ? 10 : v > 100 ? 100 : v);
  volumenHasta_ = hal_.ahoraMs() + tiemposPanel::VOLUMEN_MS;
  if (!volumenHasta_) volumenHasta_ = 1;
}

// Las pistas de los botones, abajo: a la izquierda VOL+ (lima), a la derecha VOL−.
void Sistema::dibujarPistas(const char* si, const char* no) {
  if (!perfil_.botones) return;
  const float W = static_cast<float>(lienzo_.ancho()), H = static_cast<float>(lienzo_.alto());
  const Fuente& fu = fuentes::TEXTO_13;
  const float y = H - 22, alto = 30;
  auto pista = [&](const char* signo, const char* t, float cx, uint32_t fondo, uint32_t tinta) {
    char s[40];
    const size_t n = copiarTexto(s, sizeof s, signo);
    copiarTexto(s + n, sizeof s - n, t);
    const float w = anchoTexto(fu, s) + 24;
    lienzo_.pildora(cx, y, w, alto, alto / 2, fondo);
    dibujarTexto(lienzo_, fu, s, cx - (w - 24) / 2, y + fu.ascenso * 0.36f, tinta);
  };
  if (si && si[0]) pista("+ ", si, no && no[0] ? W * 0.27f : W / 2, paleta::LIMA, paleta::PANTALLA);
  if (no && no[0]) pista("\xE2\x88\x92 ", no, si && si[0] ? W * 0.73f : W / 2, paleta::BOTON, paleta::TINTA);
}

// La barrita del volumen, abajo, encima de todo.
void Sistema::dibujarVolumen() {
  const float W = static_cast<float>(lienzo_.ancho()), H = static_cast<float>(lienzo_.alto());
  const float cx = W / 2, y = H - 26, bw = W * 0.56f;
  lienzo_.opacidad(1);
  lienzo_.pildora(cx, y, bw + 56, 34, 17, paleta::LINEA);
  // El parlantito.
  const float px = cx - bw / 2 - 12;
  const Punto parlante[6] = {{px - 7, y - 3}, {px - 3, y - 3}, {px + 3, y - 8}, {px + 3, y + 8}, {px - 3, y + 3}, {px - 7, y + 3}};
  lienzo_.poligono(parlante, 6, paleta::TINTA);
  const float x0 = cx - bw / 2 + 8, ancho = bw - 4;
  lienzo_.pildora(x0 + ancho / 2, y, ancho, 8, 4, paleta::BOTON);
  const float w = ancho * config_.voz.volumen / 100.0f;
  if (w >= 1) lienzo_.pildora(x0 + w / 2, y, w, 8, 4, colorOjos());
}

}  // namespace sintetica
