#include "oido.h"

#include "mate.h"

namespace sintetica {

namespace {
constexpr int SEGUNDO_MS = 1000, VOZ_MS = 1500, MUSICA_MS = 8000;
constexpr uint32_t SILENCIO_MS = 10 * 60 * 1000;

// log2 sin libc: el exponente del float y un polinomio para la mantisa (error < 0,01).
float log2Rapido(float x) {
  union {
    float f;
    uint32_t i;
  } u{x};
  const float e = static_cast<float>(static_cast<int32_t>((u.i >> 23) & 0xFF) - 128);  // el polinomio ya suma el 1
  u.i = (u.i & 0x007FFFFF) | 0x3F800000;  // mantisa en [1, 2)
  const float m = u.f;
  return e + (-0.34484843f * m + 2.02466578f) * m - 0.67487759f;
}
}  // namespace

float dbfs(const int16_t* m, size_t n) {
  if (!n) return -96;
  float s = 0;
  for (size_t i = 0; i < n; i++) s += static_cast<float>(m[i]) * m[i];
  const float rms = raiz(s / n) / 32768.0f;
  if (rms < 1e-5f) return -96;
  return maxf(-96, 6.0206f * log2Rapido(rms));  // 20·log10(x) = 6,0206·log2(x)
}

float Oido::promedio(int n) const {
  if (n_ == 0) return 0;
  n = mini(n, n_);
  float s = 0;
  for (int i = 1; i <= n; i++) s += historia_[(pos_ - i + MAX_HISTORIA) % MAX_HISTORIA];
  return s / n;
}

float Oido::sobrePiso(int n) const {
  if (n_ < n) return 0;
  int c = 0;
  for (int i = 1; i <= n; i++) {
    const float h = historia_[(pos_ - i + MAX_HISTORIA) % MAX_HISTORIA];
    if (h > piso_ + 10 && h > -50) c++;
  }
  return static_cast<float>(c) / n;
}

Evento Oido::nivelDb(float db) {
  ms_ += tramoMs_;
  const float antes = n_ ? promedio(cuantos(SEGUNDO_MS)) : db;
  historia_[pos_] = db;
  pos_ = (pos_ + 1) % MAX_HISTORIA;
  if (n_ < MAX_HISTORIA) n_++;
  // El piso baja rápido y sube muy lento: sigue el ruido de fondo de la pieza.
  piso_ = db < piso_ ? piso_ + (db - piso_) * 0.3f : piso_ + (db - piso_) * 0.002f;
  nivel_ = limitar((db - piso_ - 6) / 30, 0, 1);

  Evento r = Evento::Cantidad;
  const float voz = sobrePiso(cuantos(VOZ_MS));
  if (db > -25 && db - antes > 20 && (!hayRuido_ || ms_ - ultimoRuido_ > 3000)) {
    r = Evento::Ruido, hayRuido_ = true, ultimoRuido_ = ms_;
  } else if (sobrePiso(cuantos(MUSICA_MS)) >= 0.92f && (!hayMusica_ || ms_ - ultimaMusica_ > 60000)) {
    r = Evento::Musica, hayMusica_ = true, ultimaMusica_ = ms_;
  } else if (voz >= 0.25f && voz <= 0.85f && (!hayVoz_ || ms_ - ultimaVoz_ > 8000) &&
             (!hayMusica_ || ms_ - ultimaMusica_ > 20000)) {
    r = Evento::Voz, hayVoz_ = true, ultimaVoz_ = ms_;
  }
  if (r != Evento::Cantidad || db > piso_ + 12) {
    ultimoSonido_ = ms_;
    avisoSilencio_ = false;
  } else if (!avisoSilencio_ && ms_ - ultimoSonido_ >= SILENCIO_MS) {
    avisoSilencio_ = true;
    return Evento::Silencio;
  }
  return r;
}

}  // namespace sintetica
