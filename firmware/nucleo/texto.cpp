#include "texto.h"

namespace sintetica {

namespace {
const Glifo* buscar(const Fuente& f, uint32_t cp) {
  int lo = 0, hi = f.cantidad - 1;
  while (lo <= hi) {
    int m = (lo + hi) / 2;
    if (f.glifos[m].codigo == cp) return &f.glifos[m];
    if (f.glifos[m].codigo < cp) lo = m + 1;
    else hi = m - 1;
  }
  return nullptr;
}

float avanceDe(const Fuente& f, uint32_t cp) {
  const Glifo* g = buscar(f, cp);
  if (!g) g = buscar(f, ' ');
  return g ? g->avance / 16.0f : 0;
}
}  // namespace

uint32_t siguienteCodigo(const char** p) {
  const auto* s = reinterpret_cast<const uint8_t*>(*p);
  uint32_t c = s[0];
  int n = 1;
  if (c >= 0xF0) c &= 0x07, n = 4;
  else if (c >= 0xE0) c &= 0x0F, n = 3;
  else if (c >= 0xC0) c &= 0x1F, n = 2;
  for (int i = 1; i < n; i++) {
    if ((s[i] & 0xC0) != 0x80) {
      *p += i;
      return 0xFFFD;
    }
    c = (c << 6) | (s[i] & 0x3F);
  }
  *p += n;
  return c;
}

float anchoTexto(const Fuente& f, const char* s) {
  float x = 0;
  bool primero = true;
  while (*s) {
    uint32_t cp = siguienteCodigo(&s);
    if (!primero) x += f.tracking;
    x += avanceDe(f, cp);
    primero = false;
  }
  return x;
}

float dibujarTexto(Lienzo& l, const Fuente& f, const char* s, float x, float base, uint32_t rgb) {
  const int yb = static_cast<int>(piso(base + 0.5f));
  while (*s) {
    uint32_t cp = siguienteCodigo(&s);
    const Glifo* g = buscar(f, cp);
    if (g && g->w && g->h) {
      const int gx = static_cast<int>(piso(x + 0.5f)) + g->x;
      const int gy = yb + g->y;
      for (int j = 0; j < g->h; j++) {
        for (int i = 0; i < g->w; i++) {
          const uint32_t k = static_cast<uint32_t>(j * g->w + i);
          const uint8_t b = f.datos[g->datos + k / 2];
          const uint8_t a = (k & 1) ? (b & 0x0F) : (b >> 4);
          const int px = gx + i, py = gy + j;
          if (a && px >= 0 && py >= 0 && px < l.ancho() && py < l.alto()) l.cubrir(px, py, a / 15.0f, rgb);
        }
      }
    }
    x += (g ? g->avance / 16.0f : avanceDe(f, ' ')) + f.tracking;
  }
  return x - f.tracking;
}

}  // namespace sintetica
