// Los sonidos con nombre (Hal::sonido: "hip", "achis", "ronquido",
// "despertador:3"…) sintetizados en el núcleo, para los robots que tienen
// parlante y no se los arman solos (el cubito): salen por Hal::audio, PCM de
// 16 bits, 16 kHz, mono, de a bloques. El mismo repertorio que el robot-celu
// (android-bicho, Voz.kt): notas que suben o bajan desde un tono base (el de
// voz.tipo) y unos pocos de ruido.
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace sintetica {

class Sonidos {
 public:
  // Empieza el sonido `nombre` con la voz de la config (0 grave, 1 media,
  // 2 aguda, 3 robot) y el volumen (0-100). false si no hay nada que sonar.
  bool empezar(const char* nombre, int tipo, int volumen);
  void parar() { n_ = 0; }
  bool sonando() const { return actual_ < n_; }
  // Llena hasta n muestras; devuelve cuántas (menos que n: terminó).
  size_t generar(int16_t* muestras, size_t n);

  static constexpr int MAX_TRAMOS = 16;

 private:
  enum class Tipo : uint8_t { Tono, Ruido, Ronroneo, Ronquido };
  struct Tramo {
    Tipo tipo;
    float f0, f1;        // en veces la base (en el tono)
    uint16_t ms, silencio;
    float fuerza;
  };
  void sumar(Tipo t, float f0, float f1, int ms, int silencio, float fuerza);
  float muestra(const Tramo& t, uint32_t i, uint32_t n);
  float azar();

  Tramo tramos_[MAX_TRAMOS];
  int n_ = 0, actual_ = 0;
  uint32_t i_ = 0;  // la muestra dentro del tramo (con su silencio)
  float base_ = 400, volumen_ = 0.7f, fase_ = 0, y_ = 0, decae_ = 1;
  bool robot_ = false;
  uint32_t semilla_ = 0x5157E71Cu;
};

}  // namespace sintetica
