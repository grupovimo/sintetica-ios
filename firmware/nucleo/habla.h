// Que el bicho hable solo: frases cortas según el momento y su carácter, en un
// globo de texto. Las frases son datos (shared/formato/vida/frases.json,
// embebidas en vida_base.h como tabla, en la flash); el usuario suma las suyas
// en la config ("habla"). El motor de vida pide una situación (la acción
// "decir:<situación>" de las reglas, el campo "decir" de los pasos, los hitos)
// y el Hablador decide si de verdad habla: con probabilidad, enfriamiento por
// situación, separación mínima y un tope por día, para no ser pesado.
#pragma once

#include "json.h"
#include "mate.h"
#include "vida_datos.h"

namespace sintetica {

constexpr int LARGO_FRASE = 61;          // 60 bytes UTF-8 + terminador (lo mismo que el comando Decir)
constexpr int MAX_FRASES_PROPIAS = 12;   // en total, entre todas las situaciones

// Los nombres son los de frases.json y los de "habla.propias" (ASCII).
enum class Situacion : uint8_t {
  Despertar, BuenasNoches, Volviste, TeExtrane, Aburrido, Sueno, BateriaBaja, Cargando, Caricia, Saludo,
  Hito, CumpleDueno, CumpleRobot, RecordatorioHecho, Despertador, Posponer,
  ClimaFrio, ClimaCalor, ClimaLluvia, ClimaLindo,
  Cantidad
};
constexpr int N_SITUACIONES = static_cast<int>(Situacion::Cantidad);
const char* nombreSituacion(Situacion s);
bool situacionPorNombre(const char* n, size_t largo, Situacion* s);

struct FrasePropia {
  Situacion situacion = Situacion::Despertar;
  char texto[LARGO_FRASE] = {};
};

// "habla" de la config v2.
struct Habla {
  uint8_t frecuencia = 50;   // centésimos (0 = nunca habla solo; 100 = el doble que lo normal)
  uint8_t nPropias = 0;
  FrasePropia propias[MAX_FRASES_PROPIAS];
};

// "despertador" de la config v2: uno solo por bicho.
struct Despertador {
  bool hay = false;
  bool activo = true;
  bool sonido = true;
  uint16_t minuto = 0;        // del día
  uint8_t dias = 0x7F;        // bit 0 lunes … bit 6 domingo
  uint8_t posponer = 9;       // minutos (1-30)
  char texto[LARGO_FRASE] = {};  // vacío = una frase de "despertador"
};

// Lee "habla", "despertador" y "ubicacion" (esta la usa la nube: acá solo se
// valida). nullptr si está bien; si no, el motivo.
const char* leerHabla(const Json& j, int raiz, Habla* h);
const char* leerDespertador(const Json& j, int raiz, Despertador* d);
const char* validarUbicacion(const Json& j, int raiz);

// Reemplaza {dueno} y {robot} y corta en `cap - 1` bytes sin partir una letra.
// Sin dueño, se lleva la coma o el espacio de antes ("¡Hola, {dueno}!" → "¡Hola!").
size_t completarFrase(const char* plantilla, const char* dueno, const char* robot, char* salida, size_t cap);

// El preset más parecido a esa personalidad (los de personalidades.json),
// para elegir las variantes de las frases.
const char* presetCercano(const Personalidad& p);

// Elige una frase de la situación: las propias del usuario (si tiene) pesan
// más; si no, las de fábrica para todos y las de su preset (doble peso). Sin
// dueño, saltea las que empiezan con {dueno}. false si no hay ninguna.
bool elegirFrase(const Habla& h, Situacion s, const char* preset, const char* dueno, const char* robot, Azar& azar,
                 char* salida, size_t cap);

// Lo que decide si habla o no (en RAM: unos pocos bytes).
class Hablador {
 public:
  // ¿Habla ahora? `segundos` es un reloj que avanza (los del sistema); `dia`,
  // el día del calendario (0 si no se sabe). Si dice que sí, ya lo anotó.
  bool quiere(Situacion s, uint32_t segundos, uint32_t dia, uint8_t frecuencia, Azar& azar);
  // Para los tests.
  int hoy() const { return hoy_; }

 private:
  uint32_t ultima_[N_SITUACIONES] = {};
  bool hubo_[N_SITUACIONES] = {};
  uint32_t ultimaCualquiera_ = 0;
  bool huboAlguna_ = false;
  uint32_t dia_ = 0;
  uint32_t diaDesde_ = 0;   // sin calendario: un "día" cada 24 h de reloj
  uint8_t hoy_ = 0;
};

// La duración del globo según el largo: 2,5 s + 60 ms por byte, entre 3 y 10 s.
uint32_t duracionGlobo(const char* texto);

}  // namespace sintetica
