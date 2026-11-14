// El oído: de cada tramo del micrófono solo se queda con el nivel (RMS en
// dBFS) y decide si hubo voz, un ruido fuerte, música o un silencio largo.
// No guarda audio. El mismo criterio que el robot-celu (android-bicho, Oido.kt):
//
// - Ruido: un salto de más de 20 dB sobre el último segundo, bien fuerte.
// - Voz: en los últimos 1,5 s, entre el 25 % y el 85 % de los tramos sobre el
//   piso (la voz va y viene con las sílabas).
// - Música: 8 s seguidos con casi todos los tramos sobre el piso.
// - Silencio: 10 min sin nada de lo anterior.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "formato.h"

namespace sintetica {

// dBFS de un tramo de PCM de 16 bits (−96 sin sonido).
float dbfs(const int16_t* m, size_t n);

class Oido {
 public:
  explicit Oido(int tramoMs = 20) : tramoMs_(tramoMs) {}
  // Mide un tramo (su nivel ya en dBFS); devuelve lo que oyó o
  // Evento::Cantidad si nada.
  Evento nivelDb(float db);
  Evento tramo(const int16_t* m, size_t n) { return nivelDb(dbfs(m, n)); }
  // Nivel de 0 a 1 por encima del piso (para que la cara lo siga).
  float nivel() const { return nivel_; }
  float piso() const { return piso_; }

  static constexpr int MAX_HISTORIA = 400;  // 8 s de tramos de 20 ms

 private:
  int cuantos(int ms) const { return ms / tramoMs_; }
  float sobrePiso(int n) const;
  float promedio(int n) const;

  int tramoMs_;
  float historia_[MAX_HISTORIA] = {};
  int n_ = 0, pos_ = 0;  // cuántos hay y dónde va el próximo
  float piso_ = -60, nivel_ = 0;
  uint32_t ms_ = 0;
  uint32_t ultimoRuido_ = 0, ultimaVoz_ = 0, ultimaMusica_ = 0, ultimoSonido_ = 0;
  bool hayRuido_ = false, hayVoz_ = false, hayMusica_ = false, avisoSilencio_ = false;
};

}  // namespace sintetica
