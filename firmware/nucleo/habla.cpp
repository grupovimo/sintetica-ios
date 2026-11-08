#include "habla.h"

#include "formato.h"
#include "vida_base.h"

namespace sintetica {

namespace {
const char* const NOMBRES_SITUACION[N_SITUACIONES] = {
    "despertar", "buenas-noches", "volviste", "te-extrane", "aburrido", "sueno", "bateria-baja", "cargando",
    "caricia", "saludo", "hito", "cumple-dueno", "cumple-robot", "recordatorio-hecho", "despertador", "posponer",
    "clima-frio", "clima-calor", "clima-lluvia", "clima-lindo"};

const char* const PRESETS[] = {"equilibrado", "timido", "picaro", "dormilon", "carinoso", "curioso", "grunon", "electrico"};

// La fila de la tabla de fábrica de esa situación (nullptr si no tiene).
const SituacionBase* base(Situacion s) {
  const char* n = nombreSituacion(s);
  for (int i = 0; i < CANTIDAD_SITUACIONES_BASE; i++)
    if (iguales(SITUACIONES_BASE[i].nombre, n)) return &SITUACIONES_BASE[i];
  return nullptr;
}

bool esBool(const Json& j, int t) { return j.tipo(t) == TipoJson::Verdadero || j.tipo(t) == TipoJson::Falso; }

// Solo esas claves en el objeto.
template <size_t N>
bool soloEstas(const Json& j, int obj, const char* const (&claves)[N]) {
  int k = obj + 1;
  for (int i = 0; i < j.cantidad(obj); i++, k = j.saltar(k + 1)) {
    char c[16];
    if (j.texto(k, c, sizeof c) <= 0) return false;
    bool ok = false;
    for (size_t n = 0; n < N && !ok; n++) ok = iguales(c, claves[n]);
    if (!ok) return false;
  }
  return true;
}

bool utf8Valido(const char* s) {
  const auto* p = reinterpret_cast<const uint8_t*>(s);
  while (*p) {
    int n = *p < 0x80 ? 1 : (*p >> 5) == 6 ? 2 : (*p >> 4) == 14 ? 3 : (*p >> 3) == 30 ? 4 : 0;
    if (!n) return false;
    for (int i = 1; i < n; i++)
      if ((p[i] & 0xC0) != 0x80) return false;
    p += n;
  }
  return true;
}

// Un texto de 1 a 60 bytes. -1 si no es texto, 0 si es vacío o muy largo.
int leerFrase(const Json& j, int t, char* destino) {
  char buf[LARGO_FRASE + 8];
  if (!j.valido(t) || j.tipo(t) != TipoJson::Texto) return -1;
  const int n = j.texto(t, buf, sizeof buf);
  if (n < 1 || n >= LARGO_FRASE || !utf8Valido(buf)) return 0;
  copiarTexto(destino, LARGO_FRASE, buf);
  return n;
}

bool hora(const char* s, uint16_t* minuto) {
  auto d = [](char c) { return c >= '0' && c <= '9'; };
  if (largo(s) != 5 || !d(s[0]) || !d(s[1]) || s[2] != ':' || !d(s[3]) || !d(s[4])) return false;
  const int h = (s[0] - '0') * 10 + (s[1] - '0'), m = (s[3] - '0') * 10 + (s[4] - '0');
  if (h > 23 || m > 59) return false;
  *minuto = static_cast<uint16_t>(h * 60 + m);
  return true;
}

// Corta en `max` bytes sin partir una letra de varios bytes.
size_t cortarUtf8(const char* s, size_t n, size_t max) {
  if (n <= max) return n;
  size_t k = max;
  while (k > 0 && (static_cast<uint8_t>(s[k]) & 0xC0) == 0x80) k--;
  return k;
}
}  // namespace

const char* nombreSituacion(Situacion s) {
  const int i = static_cast<int>(s);
  return i < N_SITUACIONES ? NOMBRES_SITUACION[i] : "";
}

bool situacionPorNombre(const char* n, size_t l, Situacion* s) {
  for (int i = 0; i < N_SITUACIONES; i++) {
    if (largo(NOMBRES_SITUACION[i]) == l && iguales(NOMBRES_SITUACION[i], n, l)) {
      *s = static_cast<Situacion>(i);
      return true;
    }
  }
  return false;
}

const char* leerHabla(const Json& j, int raiz, Habla* h) {
  const int ha = j.buscar(raiz, "habla");
  if (ha < 0) return nullptr;
  if (j.tipo(ha) != TipoJson::Objeto) return "habla: no es un objeto";
  static const char* const CLAVES[] = {"frecuencia", "propias"};
  if (!soloEstas(j, ha, CLAVES)) return "habla: claves válidas: frecuencia y propias";
  Habla nuevo;
  const int fr = j.buscar(ha, "frecuencia");
  if (fr >= 0) {
    const float f = j.numero(fr, -1);
    if (j.tipo(fr) != TipoJson::Numero || f < 0 || f > 1) return "habla: frecuencia de 0 a 1";
    nuevo.frecuencia = static_cast<uint8_t>(f * 100 + 0.5f);
  }
  const int pr = j.buscar(ha, "propias");
  if (pr >= 0) {
    if (j.tipo(pr) != TipoJson::Objeto) return "habla: propias es un objeto (situación → lista de frases)";
    int k = pr + 1;
    for (int i = 0; i < j.cantidad(pr); i++, k = j.saltar(k + 1)) {
      char nombre[24];
      Situacion s;
      const int nl = j.texto(k, nombre, sizeof nombre);
      if (nl <= 0 || !situacionPorNombre(nombre, static_cast<size_t>(nl), &s)) return "habla: situación desconocida";
      const int lista = k + 1;
      if (j.tipo(lista) != TipoJson::Arreglo) return "habla: cada situación es una lista de frases";
      for (int e = 0; e < j.cantidad(lista); e++) {
        if (nuevo.nPropias >= MAX_FRASES_PROPIAS) return "habla: hasta 12 frases propias en total";
        FrasePropia& f = nuevo.propias[nuevo.nPropias];
        if (leerFrase(j, j.elemento(lista, e), f.texto) <= 0) return "habla: cada frase de 1 a 60 bytes (una tilde ocupa 2)";
        f.situacion = s;
        nuevo.nPropias++;
      }
    }
  }
  *h = nuevo;
  return nullptr;
}

const char* leerDespertador(const Json& j, int raiz, Despertador* d) {
  const int de = j.buscar(raiz, "despertador");
  if (de < 0) return nullptr;
  if (j.tipo(de) != TipoJson::Objeto) return "despertador: no es un objeto";
  static const char* const CLAVES[] = {"hora", "dias", "activo", "sonido", "texto", "posponer"};
  if (!soloEstas(j, de, CLAVES)) return "despertador: claves válidas: hora, dias, activo, sonido, texto y posponer";
  Despertador n;
  n.hay = true;
  char t[8];
  const int ho = j.buscar(de, "hora");
  if (ho < 0 || j.texto(ho, t, sizeof t) <= 0 || !hora(t, &n.minuto)) return "despertador: hora es HH:MM (obligatoria)";
  const int di = j.buscar(de, "dias");
  if (di >= 0) {
    char s[12];
    const int k = j.texto(di, s, sizeof s);
    if (k < 0 || k > 7 || !leerDias(s, &n.dias))
      return "despertador: dias son letras de L M X J V S D, sin repetir (vacío = todos)";
  }
  const int ac = j.buscar(de, "activo"), so = j.buscar(de, "sonido");
  if ((ac >= 0 && !esBool(j, ac)) || (so >= 0 && !esBool(j, so))) return "despertador: activo y sonido son true o false";
  n.activo = j.booleano(ac, true);
  n.sonido = j.booleano(so, true);
  const int te = j.buscar(de, "texto");
  if (te >= 0 && leerFrase(j, te, n.texto) <= 0) return "despertador: texto de 1 a 60 bytes (una tilde ocupa 2)";
  const int po = j.buscar(de, "posponer");
  if (po >= 0) {
    const float v = j.numero(po, -1);
    if (j.tipo(po) != TipoJson::Numero || v < 1 || v > 30 || v != static_cast<float>(static_cast<int>(v)))
      return "despertador: posponer en minutos, de 1 a 30";
    n.posponer = static_cast<uint8_t>(v);
  }
  *d = n;
  return nullptr;
}

const char* validarUbicacion(const Json& j, int raiz) {
  const int u = j.buscar(raiz, "ubicacion");
  if (u < 0) return nullptr;
  if (j.tipo(u) != TipoJson::Objeto) return "ubicacion: no es un objeto";
  static const char* const CLAVES[] = {"lat", "lon", "ciudad"};
  if (!soloEstas(j, u, CLAVES)) return "ubicacion: claves válidas: lat, lon y ciudad";
  const int la = j.buscar(u, "lat"), lo = j.buscar(u, "lon"), ci = j.buscar(u, "ciudad");
  if (la < 0 || j.tipo(la) != TipoJson::Numero || j.numero(la, 99) < -90 || j.numero(la, 99) > 90)
    return "ubicacion: lat de -90 a 90 (obligatoria)";
  if (lo < 0 || j.tipo(lo) != TipoJson::Numero || j.numero(lo, 999) < -180 || j.numero(lo, 999) > 180)
    return "ubicacion: lon de -180 a 180 (obligatoria)";
  if (ci >= 0) {
    char c[48];
    const int n = j.tipo(ci) == TipoJson::Texto ? j.texto(ci, c, sizeof c) : -1;
    if (n < 1 || n > 40) return "ubicacion: ciudad de 1 a 40 bytes";
  }
  return nullptr;
}

size_t completarFrase(const char* p, const char* dueno, const char* robot, char* salida, size_t cap) {
  if (cap == 0) return 0;
  const bool hayDueno = dueno && dueno[0];
  // Se arma entero y se corta al final, sin partir una letra.
  char buf[256];
  size_t m = 0;
  auto agregar = [&](const char* s, size_t k) {
    for (size_t i = 0; i < k && m < sizeof buf - 1; i++) buf[m++] = s[i];
  };
  for (const char* c = p; *c;) {
    if (*c == '{') {
      if (iguales(c, "{dueno}", 7)) {
        if (hayDueno) {
          agregar(dueno, largo(dueno));
        } else {
          // Se lleva la coma y el espacio de antes: "¡Hola, {dueno}!" → "¡Hola!".
          while (m > 0 && (buf[m - 1] == ' ' || buf[m - 1] == ',')) m--;
          // Y si quedó al principio ("{dueno}, ¿me cargás?"), lo de después.
          if (m == 0)
            while (c[7] == ',' || c[7] == ' ') c++;
        }
        c += 7;
        continue;
      }
      if (iguales(c, "{robot}", 7)) {
        agregar(robot ? robot : "", largo(robot));
        c += 7;
        continue;
      }
    }
    agregar(c, 1);
    c++;
  }
  buf[m] = 0;
  const size_t n = cortarUtf8(buf, m, cap - 1);
  copiarTexto(salida, cap, buf, n);
  return n;
}

const char* presetCercano(const Personalidad& p) {
  const char* mejor = PRESETS[0];
  float dMejor = 1e9f;
  for (const char* n : PRESETS) {
    Personalidad q;
    if (!presetPersonalidad(n, &q)) continue;
    float d = 0;
    for (int i = 0; i < N_RASGOS; i++) d += (p[i] - q[i]) * (p[i] - q[i]);
    if (d < dMejor) dMejor = d, mejor = n;
  }
  return mejor;
}

bool elegirFrase(const Habla& h, Situacion s, const char* preset, const char* dueno, const char* robot, Azar& azar,
                 char* salida, size_t cap) {
  const bool hayDueno = dueno && dueno[0];
  auto sirve = [&](const char* t) { return hayDueno || !iguales(t, "{dueno}", 7); };
  // Las propias del usuario: si tiene para esta situación, solo esas (son su voz).
  int propias = 0;
  for (int i = 0; i < h.nPropias; i++)
    if (h.propias[i].situacion == s && sirve(h.propias[i].texto)) propias++;
  if (propias > 0) {
    int k = static_cast<int>(azar.entre(0, static_cast<uint32_t>(propias - 1)));
    for (int i = 0; i < h.nPropias; i++) {
      if (h.propias[i].situacion != s || !sirve(h.propias[i].texto)) continue;
      if (k-- == 0) {
        completarFrase(h.propias[i].texto, dueno, robot, salida, cap);
        return true;
      }
    }
  }
  const SituacionBase* b = base(s);
  if (!b) return false;
  // Peso 1 las de todos, 2 las de su preset; las de otros presets, nada.
  auto peso = [&](const FraseBase& f) {
    if (!sirve(f.texto)) return 0;
    if (!f.preset[0]) return 1;
    return preset && iguales(f.preset, preset) ? 2 : 0;
  };
  int total = 0;
  for (int i = 0; i < b->cantidad; i++) total += peso(FRASES_BASE[b->primera + i]);
  if (total == 0) return false;
  int k = static_cast<int>(azar.entre(0, static_cast<uint32_t>(total - 1)));
  for (int i = 0; i < b->cantidad; i++) {
    const FraseBase& f = FRASES_BASE[b->primera + i];
    k -= peso(f);
    if (k < 0) {
      completarFrase(f.texto, dueno, robot, salida, cap);
      return true;
    }
  }
  return false;
}

bool Hablador::quiere(Situacion s, uint32_t segundos, uint32_t dia, uint8_t frecuencia, Azar& azar) {
  const SituacionBase* b = base(s);
  if (!b) return false;
  const int i = static_cast<int>(s);
  // Un día nuevo (o, sin calendario, 24 h de reloj): vuelve a cero el tope.
  if (dia ? dia != dia_ : segundos - diaDesde_ >= 86400u) {
    dia_ = dia, diaDesde_ = segundos, hoy_ = 0;
  }
  if (!b->siempre) {
    if (frecuencia == 0) return false;
    const float f = frecuencia / 50.0f;  // 0,5 → ×1
    if (hoy_ >= static_cast<int>(FRASES_POR_DIA * f + 0.5f)) return false;
    if (huboAlguna_ && segundos - ultimaCualquiera_ < static_cast<uint32_t>(FRASES_SEPARACION_S / f)) return false;
    if (hubo_[i] && segundos - ultima_[i] < static_cast<uint32_t>(b->enfriamiento)) return false;
    if (azar.real() >= minf(1, b->probabilidad / 100.0f * f)) return false;
    hoy_++;
    ultimaCualquiera_ = segundos, huboAlguna_ = true;
  }
  ultima_[i] = segundos, hubo_[i] = true;
  return true;
}

uint32_t duracionGlobo(const char* texto) {
  const uint32_t ms = 2500 + 60 * static_cast<uint32_t>(largo(texto));
  return ms < 3000 ? 3000 : ms > 10000 ? 10000 : ms;
}

}  // namespace sintetica
