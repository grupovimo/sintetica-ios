#include "sonidos.h"

#include "mate.h"

namespace sintetica {

namespace {
constexpr int TASA = 16000;

bool es(const char* a, const char* b) { return iguales(a, b); }
}  // namespace

void Sonidos::sumar(Tipo t, float f0, float f1, int ms, int silencio, float fuerza) {
  if (n_ < MAX_TRAMOS)
    tramos_[n_++] = {t, f0, f1, static_cast<uint16_t>(ms), static_cast<uint16_t>(silencio), fuerza};
}

bool Sonidos::empezar(const char* nombre, int tipo, int volumen) {
  n_ = actual_ = 0;
  i_ = 0;
  fase_ = y_ = 0;
  if (!nombre || !nombre[0] || volumen <= 0) return false;
  base_ = tipo == 0 ? 260.0f : tipo == 2 ? 620.0f : 400.0f;
  robot_ = tipo == 3;
  volumen_ = limitar(volumen / 100.0f, 0, 1);
  const Tipo T = Tipo::Tono;
  if (iguales(nombre, "despertador:", 12)) {
    // Tres pitidos, más fuertes según el nivel (1 a 5), siempre a todo volumen.
    const int nivel = maxi(1, mini(5, nombre[12] - '0'));
    const float f = 0.25f + 0.75f * (nivel - 1) / 4.0f;
    base_ = 440, robot_ = false, volumen_ = 1;
    for (int i = 0; i < 3; i++) sumar(T, 2, 2, 120, 100, f);
  } else if (es(nombre, "llamar")) {
    sumar(T, 1, 1.5f, 120, 30, 1), sumar(T, 1.2f, 1.8f, 150, 30, 1);
  } else if (es(nombre, "risa")) {
    for (int i = 0; i < 4; i++) sumar(T, 1.45f - i * 0.05f, 1.1f, 90, 40, 1);
  } else if (es(nombre, "tarareo")) {
    const float notas[5] = {1, 1.12f, 1.26f, 1.12f, 1};
    for (float f : notas) sumar(T, f, f, 220, 20, 0.6f);
  } else if (es(nombre, "hip")) {
    sumar(T, 1.6f, 2, 70, 30, 1);
  } else if (es(nombre, "festejo")) {
    sumar(T, 1, 1.5f, 100, 30, 1), sumar(T, 1.25f, 1.9f, 100, 30, 1), sumar(T, 1.5f, 2.2f, 180, 30, 1);
  } else if (es(nombre, "ayuda")) {
    sumar(T, 1.3f, 0.9f, 300, 80, 1), sumar(T, 1.2f, 0.8f, 350, 30, 1);
  } else if (es(nombre, "achis")) {
    sumar(T, 1.2f, 1.6f, 150, 60, 1), sumar(Tipo::Ruido, 0, 0, 180, 0, 0.5f);
  } else if (es(nombre, "murmullo") || es(nombre, "hablando")) {
    for (int i = 0; i < 3; i++) sumar(T, 0.7f + i * 0.06f, 0.65f, 110, 50, 0.45f);
  } else if (es(nombre, "escuchando")) {
    sumar(T, 1, 1.3f, 90, 0, 0.5f);
  } else if (es(nombre, "pensando")) {
    sumar(T, 1, 1, 80, 40, 0.5f), sumar(T, 1.1f, 1.1f, 80, 0, 0.5f);
  } else if (es(nombre, "notificacion")) {
    sumar(T, 1.5f, 1.5f, 90, 30, 1), sumar(T, 2, 2, 140, 30, 1);
  } else if (es(nombre, "llamada")) {
    for (int i = 0; i < 8; i++) sumar(T, i % 2 ? 2 : 1.5f, i % 2 ? 2 : 1.5f, 60, 10, 1);
  } else if (es(nombre, "recordatorio")) {
    sumar(T, 1, 1, 150, 30, 1), sumar(T, 1.26f, 1.26f, 150, 30, 1), sumar(T, 1.5f, 1.5f, 250, 30, 1);
  } else if (es(nombre, "pomodoro")) {
    sumar(T, 1.5f, 1.5f, 200, 30, 1), sumar(T, 1, 1, 300, 30, 1);
  } else if (es(nombre, "toque")) {
    sumar(T, 1.4f, 1.8f, 70, 40, 0.7f), sumar(T, 1.6f, 2, 70, 0, 0.7f);
  } else if (es(nombre, "abrazo")) {
    sumar(T, 0.9f, 1.2f, 250, 40, 0.6f), sumar(T, 1.2f, 1, 350, 0, 0.5f);
  } else if (es(nombre, "beso")) {
    sumar(T, 2.2f, 1.6f, 60, 20, 0.6f);
  } else if (es(nombre, "agenda")) {
    sumar(T, 1.26f, 1.26f, 120, 60, 1), sumar(T, 1.26f, 1.26f, 120, 60, 1), sumar(T, 1, 1, 200, 30, 1);
  } else if (es(nombre, "pago")) {
    sumar(T, 1.5f, 1.5f, 70, 20, 1), sumar(T, 2, 2, 70, 20, 1), sumar(T, 2.5f, 2.5f, 220, 30, 1);
  } else if (es(nombre, "habito")) {
    sumar(T, 1, 1.25f, 110, 20, 1), sumar(T, 1.5f, 1.5f, 220, 30, 1);
  } else if (es(nombre, "ronroneo")) {
    sumar(Tipo::Ronroneo, 0.25f, 0.25f, 1200, 0, 0.35f);
  } else if (es(nombre, "ronquido")) {
    sumar(Tipo::Ronquido, 0, 0, 1500, 0, 0.4f);
  } else if (es(nombre, "dado")) {
    for (int i = 0; i < 7; i++) sumar(Tipo::Ruido, 0, 0, 25, 40 + 25 * i, 0.6f);
  } else {
    sumar(T, 1, 1.3f, 120, 30, 1);  // cualquier otro: un piquito
  }
  return n_ > 0;
}

float Sonidos::azar() {
  semilla_ = semilla_ * 1664525u + 1013904223u;
  return static_cast<float>(semilla_ >> 8) / 8388608.0f - 1;  // -1 a 1
}

// Sube en 8 ms y baja en 25 ms: sin chasquidos.
static float envolvente(uint32_t i, uint32_t n) {
  const float sube = TASA * 8 / 1000.0f, baja = TASA * 25 / 1000.0f;
  return maxf(0, minf(1, minf(i / sube, (n - i) / baja)));
}

float Sonidos::muestra(const Tramo& t, uint32_t i, uint32_t n) {
  switch (t.tipo) {
    case Tipo::Tono: {
      const float f = base_ * mezclar(t.f0, t.f1, static_cast<float>(i) / n);
      fase_ += VUELTA * f / TASA;
      if (fase_ > VUELTA) fase_ -= VUELTA;
      const float s = seno(fase_);
      const float onda = robot_ ? (s >= 0 ? 0.6f : -0.6f) : s + 0.2f * seno(2 * fase_);
      return onda * envolvente(i, n) * t.fuerza * 0.7f;
    }
    case Tipo::Ruido:
      // Un golpe de ruido que se apaga solo (≈ e^-4 al final).
      if (i == 0) decae_ = 1;
      decae_ *= 1 - 4.0f / n;
      return azar() * t.fuerza * decae_;
    case Tipo::Ronroneo: {
      fase_ += VUELTA * base_ * t.f0 / TASA;
      if (fase_ > VUELTA) fase_ -= VUELTA;
      const float am = 0.5f + 0.5f * seno(VUELTA * 22 * i / TASA);
      return seno(fase_) * am * envolvente(i, n) * t.fuerza;
    }
    case Tipo::Ronquido:
      y_ += 0.04f * (azar() - y_);  // ruido grave (pasabajos)
      return y_ * 6 * seno(MEDIA_VUELTA * i / n) * t.fuerza;
  }
  return 0;
}

size_t Sonidos::generar(int16_t* muestras, size_t n) {
  size_t k = 0;
  while (k < n && actual_ < n_) {
    const Tramo& t = tramos_[actual_];
    const uint32_t largo = t.ms * TASA / 1000, total = largo + t.silencio * TASA / 1000;
    if (i_ >= total) {
      actual_++, i_ = 0, fase_ = 0;
      continue;
    }
    const float s = i_ < largo ? muestra(t, i_, largo) * volumen_ : 0;
    muestras[k++] = static_cast<int16_t>(limitar(s, -1, 1) * 32000);
    i_++;
  }
  return k;
}

}  // namespace sintetica
