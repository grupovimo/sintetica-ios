// El motor de vida (v2, docs/motor-de-vida.md): una sola cara viva que nunca
// se corta. Cada parámetro del rostro es un resorte; los objetivos salen de
// capas que se suman (ánimo de fondo + comportamiento + micro-vida), empujadas
// por un estado interno que cambia con el tiempo y con lo que le pasa.
//
// Todo depende del reloj y de la semilla que le pasan: con la misma semilla y
// las mismas entradas, da exactamente los mismos cuadros (los tests lo usan).
#pragma once

#include "cara.h"
#include "formato.h"
#include "mate.h"
#include "rostro.h"

namespace sintetica {

namespace tiempos {
constexpr uint32_t PASO_MS = 1000 / 60;                     // la lógica corre a 60 Hz
constexpr uint32_t LENTO_MS = 250;                          // estado, selector y ritmo: cada 250 ms
constexpr uint32_t SALTO_MS = 2000;                         // más que esto entre ticks: se salta (sin resortes)
constexpr uint32_t REACCION_MS = 3000;                      // "expresion:x" en una regla
constexpr uint32_t REFLEJO_MS = 1200;
constexpr uint32_t GUARDAR_MS = 5u * 60u * 1000u;           // el estado y la memoria, cada 5 min
constexpr uint32_t DESPIERTO_POR_TOQUE_MS = 3u * 60u * 1000u;
constexpr uint32_t AUSENCIA_SALUDO_S = 3u * 3600u;          // desde 3 h sin verte, saluda al volver
}  // namespace tiempos

// Lo que el motor necesita saber del mundo en cada tick.
struct Contexto {
  int minutoDelDia = -1;    // -1 si no se sabe la hora
  uint32_t epoch = 0;       // segundos (hora local) desde 1970; 0 si no se sabe
  int bateria = -1;         // 0-100, -1 si no hay
  int cargando = -1;        // 1, 0 o -1 si no se sabe
};

// Lo que el motor le pide al sistema (sonidos, LED, animaciones, guardar).
struct SalidasVida {
  void* ctx = nullptr;
  void (*sonido)(void* ctx, const char* nombre) = nullptr;
  void (*led)(void* ctx, uint32_t rgb) = nullptr;
  void (*animacion)(void* ctx, int indice) = nullptr;
  void (*guardar)(void* ctx, const uint8_t* datos, size_t n) = nullptr;
  // Una situación para hablar (Situacion de habla.h): el sistema decide si dice algo.
  void (*decir)(void* ctx, uint8_t situacion) = nullptr;
};

// Lo que recuerda (se guarda en flash y se sincroniza con la cuenta).
struct Memoria {
  uint32_t nacimiento = 0;          // epoch del primer día con hora
  uint32_t ultimaInteraccion = 0;   // epoch
  uint32_t rencorHasta = 0;         // epoch: hasta cuándo duda al levantarlo
  uint32_t ultimoDia = 0;           // día (epoch / 86400) de la última interacción
  uint16_t dias = 0;                // días juntos (con alguna interacción)
  uint16_t racha = 0, rachaMax = 0; // días seguidos
  uint32_t caricias = 0, toques = 0, sacudidas = 0;
  uint8_t horas[24] = {};           // a qué hora suele aparecer el dueño
  int8_t gustos[8] = {};            // cuánto le subió el ánimo cada estímulo (ver GUSTOS en el .cpp)
  uint16_t hitos = 0;               // bits: primer día, 7 días, 30, 100 caricias, 100 días, 1000 caricias
  uint16_t anioCumpleBicho = 0, anioCumpleDueno = 0;  // último año festejado
  int8_t deriva[N_RASGOS] = {};     // cómo cambió la personalidad (centésimos, ±10)
  uint8_t estado[N_ESTADO] = {};    // el estado interno guardado (0-255)
  uint32_t epochEstado = 0;
  uint16_t ausenciaMaxima = 0;      // horas
  uint8_t afectoHoy = 0;            // cuánto afecto ganó hoy (tope diario)
  // v1.7 (en los bytes que eran ceros): juegos, el día de hoy y las fechas.
  uint16_t juegosGanados = 0, juegosJugados = 0, mejorReflejo = 0;  // ms (0 = nunca)
  uint8_t hoyJuegos = 0, hoySuenos = 0, hoySonoCon = 0;  // bits: corazón, estrella, nota, oveja, pesadilla
  uint8_t hoyAnimo = 0;             // 0 sin respuesta, 1 bien, 2 más o menos, 3 mal
  uint8_t hoyEspero = 0;            // a qué hora te esperó (hora + 1; 0 = no)
  uint8_t hoyDia = 0;               // el día de los contadores de hoy (epoch/86400 % 251 + 1)
  uint8_t anioFechas = 0, fechas = 0;  // año % 256 y bits: año nuevo, navidad, amigo, niño, aniversario
  uint8_t hoyAgua = 0;              // vasos de agua recordados hoy
};
// Qué cuenta el día (MotorVida::anotarHoy).
enum class Hoy : uint8_t { Juego, JuegoGanado, Sueno, SonoCon, Animo, Espero, Agua };
constexpr size_t LARGO_MEMORIA = 112;
size_t codificarMemoria(const Memoria& m, uint8_t* salida, size_t cap);
bool decodificarMemoria(const uint8_t* d, size_t n, Memoria* m);

// Un registro de lo que pasó, para depurar (se exporta desde la app).
struct EntradaRegistro {
  uint32_t segundos = 0;   // desde que arrancó
  uint8_t tipo = 0;        // 0 evento, 1 comportamiento, 2 dormir/despertar, 3 hito, 4 recordatorio
  uint8_t dato = 0;        // el evento, el comportamiento o 1/0
};
constexpr int MAX_REGISTRO = 32;

class MotorVida {
 public:
  void iniciar(const Config* config, uint32_t semilla, uint32_t ahora);
  void salidas(const SalidasVida& s) { salidas_ = s; }
  // Config nueva: sigue con el mismo estado interno y la misma memoria.
  void reconfigurar(const Config* config);
  void tick(uint32_t ahora, const Contexto& ctx);

  // Entradas.
  void evento(Evento e, uint32_t ahora);
  // Algo que seguir con la mirada (el celu inclinado, un dedo), de -1 a 1.
  void seguir(float x, float y, uint32_t ahora);
  // De dónde vino el último estímulo (-1 a 1): la mirada lo prefiere.
  void estimulo(float x, float y) { estX_ = limitar(x, -1, 1), estY_ = limitar(y, -1, 1); }
  // La música que suena (v1.9): mueve la cabeza a ese ritmo (bpm; 0 = deja de
  // bailar). Entra y sale suave, por los resortes.
  void musica(float bpm) { ritmoBpm_ = bpm < 0 ? 0 : bpm > 240 ? 240 : bpm; }
  float ritmoMusica() const { return ritmoBpm_; }
  float pesoRitmo() const { return ritmoPeso_; }
  // Empuja una variable del estado interno (te fuiste: se aburre antes).
  void empujarEstado(VarVida v, float delta) { empujar(static_cast<int>(v), delta); }
  // Interacción sin regla (el botón del broche): cuenta como atención.
  void interaccion(uint32_t ahora);
  // Fija una cara (nombre de la config; nullptr o "" vuelve a lo automático).
  bool fijar(const char* nombre);
  void fijar(int expresion);  // compatibilidad: índice de un dibujo (-1 = automático)
  void fijar(Config::Cara c) { fija_ = c; }
  // La cara de base (la que eligió el dueño en la lista): reemplaza a la
  // neutral, no se duerme sola y las reacciones siguen funcionando.
  void base(Config::Cara c) { base_ = c; }
  void base(int dibujo);
  Config::Cara base() const { return base_; }
  // Muestra una cara un rato y vuelve sola (como "expresion:x" en una regla).
  void reaccionar(Config::Cara c, uint32_t ahora, uint32_t duracion = tiempos::REACCION_MS);
  void reaccionar(int dibujo, uint32_t ahora, uint32_t duracion = tiempos::REACCION_MS);
  // Empieza un comportamiento ya (índice en config.vida.comportamientos).
  bool comportamiento(int indice, uint32_t ahora);
  // Lo despierta o lo duerme (el broche, los tests).
  void dormir(uint32_t ahora);
  void despertar(uint32_t ahora, bool forzado);
  // La memoria, para guardarla o restaurarla (mudanza).
  const Memoria& memoria() const { return mem_; }
  void restaurarMemoria(const Memoria& m);

  // Lo que se dibuja.
  const CuadroRostro& cuadro() const { return cuadro_; }
  // La cara de imagen que se ve (índice en config.vida.caras, -1 = la SDF):
  // la de la capa (un reflejo o un paso de un comportamiento) si es de imagen;
  // si no, la "persona" (fija > estado > base > la de config.cara.expresion),
  // y las demás caras (paramétricas) la mueven con sus parámetros.
  int caraImagen() const;
  // Qué caras de imagen se pueden mostrar (bit i = vida.imagenes[i]: tiene su
  // sprite del ojo). El sistema lo actualiza cuando cambian la config o los sprites.
  void imagenesDisponibles(uint8_t mascara) { dispImagenes_ = mascara; }
  // Si hay que dibujar un dibujo de formas (una cara propia del usuario):
  // su índice y su opacidad (para el fundido). -1 = solo el rostro.
  int dibujo() const { return dibujo_; }
  float opacidadDibujo() const { return opDibujo_; }
  // El estado para los dibujos de formas (parpadeo, mirada, respiración).
  const EstadoCara& estado() const { return estadoCara_; }
  EstadoCara& estado() { return estadoCara_; }

  // Lectura (estado BLE, depuración, simulador, tests).
  const char* nombreVisible() const;
  int expresionVisible() const;  // compatibilidad: el dibujo con el nombre visible, o la neutral
  bool dormido() const { return modo_ == Modo::Dormido; }
  bool sonando() const;
  float humor() const { return estado_[1] * 2 - 1; }  // el ánimo, de -1 a 1 (la v1)
  float variable(VarVida v) const;
  const float* estadoInterno() const { return estado_; }
  Personalidad rasgos() const;  // con la deriva
  int comportamientoActual() const { return actual_; }
  const char* nombreComportamiento() const;
  int expresionFija() const { return fija_.existe() ? (fija_.dibujo >= 0 ? fija_.dibujo : 0) : -1; }
  bool hayFija() const { return fija_.existe(); }
  // Una reacción de una regla ("expresion:x") o un reflejo en curso.
  bool reaccionando(uint32_t ahora) const;
  // Los tres mejores del último sorteo del selector (nombre, puntaje).
  int candidatos(const char** nombres, float* puntajes, int max) const;
  int registro(EntradaRegistro* salida, int max) const;
  // Anota algo que pasó fuera del motor (el sistema: 4 = recordatorio, con su
  // índice; 5 = juego; 6 = ánimo).
  void anotarRegistro(uint8_t tipo, uint8_t dato) { anotar(tipo, dato); }
  // Los contadores del día en la memoria (se vuelven a cero cada día).
  void anotarHoy(Hoy que, uint8_t dato = 0);
  // Un juego: cuánto tardó en tocar (reflejos), para el récord.
  void anotarReflejo(uint16_t ms);
  // El broche: de noche, después de dormirse, puede apagar la pantalla hasta
  // la mañana. segundosHastaDespertar: -1 si no se sabe la hora.
  bool quiereSuenoProfundo() const;
  int segundosHastaDespertar() const;
  // El brillo de la pantalla que pide el ritmo diario (0 a 1).
  float brillo() const { return cuadro_.brillo; }
  // Dormido: hacia dónde está ladeado (-1, 0, 1) y si sonríe en sueños (tests).
  int ladoDormido() const { return ladoSueno_; }
  // Para los tests.
  uint32_t parpadeos() const { return parpadeos_; }
  uint32_t parpadeosDobles() const { return dobles_; }
  float parametro(int i) const { return res_[i].x; }
  float objetivo(int i) const { return obj_[i]; }
  uint32_t comportamientosEmpezados() const { return empezados_; }

 private:
  enum class Modo : uint8_t { Despierto, Dormido };
  struct Resorte {
    float x = 0, v = 0;
  };

  void paso(float dt);
  void lento(float dt);
  void saltar(uint32_t ms);
  void calcularObjetivos(float dt);
  void moverCapa(Movimiento m, float t, float* T, int cara);
  void armarCuadro(float dt);
  void microVida(float dt);
  void parpadear(bool doble, float cierre = 0.085f);
  void actualizarEstado(float dt);
  void elegirComportamiento();
  void avanzarComportamiento();
  void empezarPaso(int i, bool primera);
  void terminarComportamiento();
  void aplicarRegla(const Regla& r);
  bool cumple(const CondVida& c) const;
  bool reglaPara(Evento e);
  void empujar(int var, float delta);
  void soltar(TipoParticula t, int cuantas = 1);
  void ritmo();
  void rutinaConVos(bool volvio);
  void vidaDormido();
  void revolverseEnSuenos(bool murmurar);
  void decir(Situacion s) {
    if (salidas_.decir) salidas_.decir(salidas_.ctx, static_cast<uint8_t>(s));
  }
  void anotar(uint8_t tipo, uint8_t dato);
  void memoriaInteraccion(Evento e);
  void revisarHitos();
  void guardar();
  float ruido(float x, uint32_t canal) const;
  void cambioDeCapa(int cara, float peso);
  bool enHorarioDormir() const;
  int caraEstado();
  bool esImagen(int cara) const;
  int idxOvejas() const;

  const Config* config_ = nullptr;
  SalidasVida salidas_;
  Azar azar_;
  uint32_t semilla_ = 1;
  Contexto ctx_;
  uint32_t ahora_ = 0, inicio_ = 0, acumulado_ = 0, ultimoTick_ = 0;
  double t_ = 0;               // segundos de lógica desde que arrancó
  uint32_t pasos_ = 0;

  // Resortes de los parámetros y los de la micro-vida.
  Resorte res_[N_PARAMETROS];
  float obj_[N_PARAMETROS];
  Resorte parpadeo_, aplastar_, sacX_, sacY_;
  float parpadeoObj_ = 0;
  float rigidez_ = 1;          // multiplica k (personalidad, energía, reflejos)

  // Capas.
  Config::Cara fija_, base_;
  int capaCara_ = -1, capaAnterior_ = -1;  // cara paramétrica del comportamiento o reacción
  float capaPeso_ = 0, capaPesoAnterior_ = 0;
  float capaDesde_ = 0, capaCambio_ = -10;
  int reflejo_ = -1;
  float reflejoHasta_ = 0;
  int dibujo_ = -1;
  float opDibujo_ = 0;
  int dibujoObjetivo_ = -1;
  int8_t animoCaras_[6] = {-1, -1, -1, -1, -1, -1};
  uint8_t dispImagenes_ = 0xFF;
  int personaImagen_ = -1;  // la cara de imagen de la persona (sin la capa)
  float animoPesos_[6] = {};
  float grunonHasta_ = 0, ofendidoHasta_ = 0;

  // Comportamiento en curso.
  Comportamiento sintetico_;   // para "expresion:x" de las reglas (un paso)
  int actual_ = -1;            // índice, o -2 = el sintético
  int pasoActual_ = 0;
  int pasoCara_ = -1;
  float pasoPeso_ = 0;
  int pasoDibujo_ = -1, sinteticoDibujo_ = -1;
  float finUltimo_ = 0;
  uint8_t vecesRestantes_ = 0;
  float pasoHasta_ = 0, pasoDesde_ = 0;
  float proximoOcio_ = 0;
  float enfriadoHasta_[MAX_COMPORTAMIENTOS] = {};
  int8_t historia_[5] = {-1, -1, -1, -1, -1};
  const char* candNombres_[3] = {};
  float candPuntajes_[3] = {};
  int nCand_ = 0;
  uint32_t empezados_ = 0;
  Mirada mirada_ = Mirada::Libre;
  Parpadeo parpadeoPaso_ = Parpadeo::Normal;
  float ladoMirada_ = 1;

  // Micro-vida.
  int rafaga_ = 0;
  float proximaRafaga_ = 0;
  bool esperandoDueno_ = false;
  float proximoParpadeo_ = 1.5f, finParpadeo_ = -1, segundoParpadeo_ = -1, ultimoParpadeo_ = -10;
  float proximaSacada_ = 1, proximaMicro_ = 0.3f;
  float sacBaseX_ = 0, sacBaseY_ = 0, microX_ = 0, microY_ = 0;
  float faseResp_ = 0, faseSpin_ = 0, faseOrbita_ = 0, faseLatido_ = 0;
  float proximaPostura_ = 20, posturaTilt_ = 0, posturaEy_ = 0;
  float glitchSemilla_ = 0, proximoGlitch_ = 0;
  float seguirX_ = 0, seguirY_ = 0, seguirHasta_ = -10;
  float ritmoBpm_ = 0, ritmoPeso_ = 0, faseRitmo_ = 0, proximaNotaRitmo_ = 0;  // la música (v1.9)
  float estX_ = 0, estY_ = 0;
  float proximaParticula_ = 0;
  uint32_t parpadeos_ = 0, dobles_ = 0;
  CuadroRostro cuadro_;
  EstadoCara estadoCara_;
  float progresoCarga_ = 0;

  // Estado interno, personalidad y ritmo.
  float estado_[N_ESTADO] = {0.7f, 0.55f, 0.3f, 0.1f, 0.5f, 0.2f, 0.0f};
  float presionSueno_ = 0.2f;
  Modo modo_ = Modo::Despierto;
  bool siesta_ = false;
  float siestaHasta_ = 0, forzadoHasta_ = -1, dormidoDesde_ = 0, despiertoDesde_ = 0;
  float proximoSueno_ = 0;     // el próximo sueño (soñar) mientras duerme
  bool ovejasHoy_ = false;
  float ultimaInteraccion_ = 0;
  float proximaCuriosidad_ = 120;
  float habituacion_[static_cast<int>(Evento::Cantidad)] = {};
  int caraEstado_ = -1;
  float guardadoEn_ = 0;
  bool hayVolvio_ = false;
  bool primeroDelDia_ = false;   // la primera interacción del día (el "buen día")
  uint32_t aDormirDia_ = 0;      // el día en que ya le dijo "¿nos vamos a dormir?"
  bool hitoPendiente_ = false;
  int8_t hitoSituacion_ = -1;    // qué se dice al festejar el hito (el cumple gana)
  // La batería baja va como una capa del ánimo (no gana sobre todo).
  bool capaBateria_ = false;
  float proximaBateria_ = 0;
  // Dormido: zzz, postura, sonrisas y murmullos, ronquidos; lo que lo despierta de noche.
  float proximoZzz_ = 0, proximaPosturaSueno_ = 0, proximoGestoSueno_ = 0, proximoRonquido_ = 0;
  float sonrisaSuenoHasta_ = -10, murmulloHasta_ = -10;
  int8_t ladoSueno_ = 0;
  uint8_t vocesDormido_ = 0;
  float ausenciaHoras_ = 0;

  Memoria mem_;
  EntradaRegistro registro_[MAX_REGISTRO];
  uint8_t nRegistro_ = 0, iniRegistro_ = 0;
};

}  // namespace sintetica
