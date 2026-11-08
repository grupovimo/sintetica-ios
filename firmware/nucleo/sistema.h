// SintéticaOS: junta la configuración, el motor de vida, los gestos, las
// reglas y el protocolo. Cada perfil de hardware solo tiene que llamar a
// iniciar() una vez y a tick() en cada vuelta, y pasarle las entradas.
#pragma once

#include "cara.h"
#include "clima.h"
#include "globo.h"
#include "formato.h"
#include "gestos.h"
#include "hal.h"
#include "lienzo.h"
#include "motor_vida.h"
#include "protocolo.h"
#include "qoi.h"
#include "sprites.h"

namespace sintetica {

constexpr const char* VERSION_SINTETICAOS = "0.3.0";

// Cómo es la placa: la pantalla y qué hace su pulsador.
struct Perfil {
  int ancho = 320, alto = 172;
  int filasFranja = 0;     // 0 = la pantalla de una vez; si no, de a tantas filas
  bool redonda = false;
  // Mascota (1.47B): toque = caricia, doble toque, mantener 5 s = QR.
  // Broche: toque = lo siguiente de la lista, mantener 2 s = dormir, 8 s = QR.
  enum class Boton : uint8_t { Mascota, Broche } boton = Boton::Mascota;
  // false = mantener apretado no muestra el QR (el bicho-celu lo muestra
  // desde su menú y el toque largo queda para la cara).
  bool qrPorMantener = true;
  // Lo que va en el estado y en los manifiestos de OTA: una OTA solo se
  // acepta si es de este mismo perfil.
  const char* nombre = "sim";
  const char* version = VERSION_SINTETICAOS;
};

namespace tiemposImagen {
constexpr uint32_t VUELTA_MIN_MS = 60000;   // mientras se ve una imagen, cada 1 a 3 min
constexpr uint32_t VUELTA_MAX_MS = 180000;  // vuelve la cara
constexpr uint32_t VUELTA_DURA_MS = 2500;   // durante un par de segundos
}  // namespace tiemposImagen

namespace tiemposPanel {
constexpr uint32_t FUNDIDO_MS = 400;              // entrar y salir del panel (nunca un corte)
constexpr uint32_t RECORDATORIO_MS = 120000;      // un recordatorio queda 2 min si no lo tocan
constexpr uint32_t CARA_EN_RELOJ_MS = 15000;      // en modo reloj, un toque muestra la cara un rato
constexpr uint32_t ALARMA_MAX_MS = 10u * 60000u;  // el despertador suena como mucho 10 min
constexpr uint32_t ALARMA_TONO_MS = 4000;         // un tono cada 4 s,
constexpr uint32_t ALARMA_SUBE_MS = 10000;        // cada 10 s más fuerte (despertador:1 a despertador:5)
constexpr uint32_t ALARMA_APAGAR_MS = 1500;       // mantener apretado: apagar
constexpr uint32_t CARA_CLIMA_MS = 40000;         // en modo clima, la cara reacciona al tiempo cada 40 s
}  // namespace tiemposPanel

namespace tiemposBroche {
constexpr uint32_t TOQUE_MS = 600;
constexpr uint32_t DORMIR_MS = 2000;
constexpr uint32_t QR_MS = 8000;
}  // namespace tiemposBroche

// "ppt", "reflejos", "mirada", "dado", "moneda" (comando Jugar, v1.7).
const char* nombreJuego(int j);

class Sistema {
 public:
  // `pixeles` = ancho × filasFranja RGB565 (o ancho × alto si se dibuja de una
  // vez). Lee la configuración guardada (o usa la base).
  void iniciar(const Hal& hal, uint16_t* pixeles, const Perfil& perfil);
  void iniciar(const Hal& hal, uint16_t* pixeles, int ancho, int alto) {
    Perfil p;
    p.ancho = ancho, p.alto = alto;
    iniciar(hal, pixeles, p);
  }
  // Avanza el tiempo, dibuja y presenta un cuadro.
  void tick();

  // Entradas.
  void tacto(bool apretado);
  void imu(float ax, float ay, float az) { gestos_.imu(ax, ay, az, hal_.ahoraMs()); }
  void evento(Evento e);
  // Algo que mirar (un dedo en la pantalla táctil, la dirección del sonido), de -1 a 1.
  void seguir(float x, float y) {
    actividad();
    motor_.seguir(x, y, hal_.ahoraMs());
  }
  // La hora (lo que manda la app con el comando Hora): epoch UTC y la zona.
  void hora(uint32_t epochUtc, int zonaMinutos);
  // La hora local que conoce (0 si no sabe) y el minuto del día (-1).
  uint32_t epoch() const;
  int minutoDelDia() const;
  // Cuántos cuadros por segundo conviene dibujar: despierto 30, tranquilo 15,
  // dormido 5 (los modos de energía). El perfil espera lo que falte.
  int fpsSugerido() const;
  // El broche: de noche se apaga hasta la mañana (o hasta el botón, o hasta
  // el próximo recordatorio).
  int segundosHastaDespertar() const;
  // La superposición de depuración (comportamiento, estado, fps).
  void depurar(bool si) { depurar_ = si; }
  // Se conectó o desconectó un celu: cada conexión empieza sin autenticar.
  void bleConexion(bool conectado);
  // Una escritura en una característica BLE.
  void bleEscribir(uint8_t caracteristica, const uint8_t* datos, size_t n);
  // Lo mismo que llega por la nube (MQTT bicho/{id}/cmd: [característica][datos]).
  // La nube ya está autenticada por el broker; no puede cambiar el WiFi ni la nube.
  void nubeEscribir(uint8_t caracteristica, const uint8_t* datos, size_t n);
  // Lo que devuelve una lectura de la característica de estado.
  size_t estadoBle(uint8_t* salida, size_t cap) const;

  // WiFi y nube (v1.3). El perfil lee las credenciales guardadas y avisa cómo
  // está conectado.
  bool red(char* ssid, size_t capSsid, char* clave, size_t capClave) const;
  bool nube(char* url, size_t capUrl, char* usuario, size_t capUsuario, char* clave, size_t capClave) const;
  void conexiones(bool wifi, bool nube);
  bool wifiConectado() const { return wifi_; }
  bool redConfigurada() const { return redConfigurada_; }
  bool nubeConectada() const { return nube_; }
  // El perfil avisa cómo va una OTA (código protocolo::Codigo, 0-100 %).
  void otaProgreso(uint8_t codigo, uint8_t porcentaje, const char* detalle = nullptr);
  bool actualizando() const { return ota_ != Ota::Ninguna; }
  uint32_t crcConfig() const { return crcConfig_; }
  // Reproduce una animación de la config (-1 para). unaVez: si no, repite.
  void reproducir(int animacion, bool unaVez);
  int animacionVisible() const { return animVisible_; }
  // El recordatorio que se ve (-1 = ninguno). Un toque lo cierra.
  int recordatorioVisible() const { return recVisible_; }
  // El panel (recordatorio, reloj o pomodoro): la cara se achica arriba y
  // abajo va el texto. 0 = solo la cara, 1 = el panel entero.
  enum class Panel : uint8_t { Ninguno, Recordatorio, Reloj, Pomodoro, Globo, Despertador, Clima, Juego };
  Panel panel() const { return panel_; }
  float fasePanel() const { return fasePanel_; }
  // Pomodoro: si corre, en qué tramo está y cuánto le falta.
  bool pomodoroCorriendo() const { return pomoCorriendo_; }
  bool pomodoroDescanso() const { return pomoDescanso_; }
  uint32_t pomodoroRestanteMs() const { return pomoRestanteMs_; }
  // Lo que dice (comando Decir, sus frases): un globo con la cara achicada.
  // `hablando`: mueve la boca un rato (el comando Decir sin expresión).
  void decir(const char* texto, Config::Cara cara = {}, bool hablando = false);
  // Una situación (las pide el motor): si el Hablador quiere, dice una frase.
  void hablar(Situacion s);
  // El texto del globo que se ve (o el del despertador).
  const char* textoGlobo() const { return globoTexto_; }
  // El despertador.
  bool alarmaSonando() const { return alarma_; }
  void sonarAlarma(bool porHora);
  void posponerAlarma();
  void apagarAlarma();
  // Juegos (v1.7): 0 piedra-papel-tijera, 1 reflejos, 2 seguí la mirada, 3 dado, 4 moneda.
  enum class Juego : uint8_t { Ppt, Reflejos, Mirada, Dado, Moneda, Ninguno = 255 };
  char visibleJuego_[16] = {};
  bool jugar(Juego j);
  Juego juego() const { return juego_; }
  const char* textoJuego() const { return juegoTexto_; }
  // El "¿cómo estás?" del día: si está esperando la respuesta (toque = bien,
  // doble = más o menos, mantener = mal) y la respuesta (0, 1, 2).
  bool preguntandoAnimo() const { return preguntando_; }
  void responderAnimo(uint8_t r);
  // El clima que mandó la nube (vale 3 h).
  const DatosClima& clima() const { return clima_; }
  bool climaVigente() const { return clima_.hay && hal_.ahoraMs() - clima_.recibido < CLIMA_VALE_MS; }
  // El protector de pantalla: 0 = la cara, 1 = la imagen entera.
  float faseProtector() const { return faseProtector_; }

  const Config& config() const { return config_; }
  const MotorVida& motor() const { return motor_; }
  MotorVida& motor() { return motor_; }
  const char* nombre() const { return nombre_[0] ? nombre_ : config_.nombre; }
  const Lienzo& lienzo() const { return lienzo_; }

  // Identidad y vínculo.
  void fijarSerie(const char* serie);  // lo graba el taller al armar la unidad
  const char* serie() const { return serie_; }
  const char* identificador() const { return id_; }
  const char* codigo() const { return codigo_; }
  const char* contenidoQr() const { return qr_; }
  bool emparejando() const { return emparejando_; }
  int cantidadDeClaves() const { return nClaves_; }
  // Da por autenticada la conexión actual (vista previa local en las apps).
  void confiar() { autenticado_ = true; }
  // Pasa a lo siguiente de la lista (en el broche, un toque).
  void siguiente();
  int posicionLista() const { return posLista_; }
  // El broche pidió dormir (mantener 2 s): el perfil apaga la pantalla y entra
  // en sueño profundo; al despertar, la placa arranca de nuevo. En el
  // simulador, la pantalla queda negra hasta el próximo toque.
  bool quiereDormir() const { return apagado_; }
  void dormir();
  const Perfil& perfil() const { return perfil_; }
  void qrPorMantener(bool si) { perfil_.qrPorMantener = si; }
  // Muestra el QR para vincular otro celu un rato (lo mismo que mantener el botón).
  void mostrarQr();
  // Imágenes guardadas: largo 0 = espacio vacío.
  uint32_t largoImagen(int espacio) const { return (espacio >= 0 && espacio < MAX_IMAGENES) ? imagenes_[espacio].largo : 0; }
  // La imagen que se ve ahora (-1 = una cara).
  int imagenVisible() const { return mostrandoImagen_; }
  // Sprites guardados (0 a 11): largo 0 = vacío.
  uint32_t largoSprite(int sprite) const {
    return (sprite >= 0 && sprite < MAX_SPRITES) ? sprites_[sprite].largo : 0;
  }
  // La cara de imagen que se dibuja (los sprites ya decodificados) y cuánto se
  // ve (el fundido: 0 = la SDF, 1 = los sprites).
  const CacheSprites& cacheSprites() const { return cache_; }
  float opacidadSprites() const { return opSprites_; }

  // Vista previa de las apps: nunca muestra el QR y confía en quien escribe.
  void modoVistaPrevia() {
    vistaPrevia_ = true;
    emparejando_ = false;
    autenticado_ = true;
  }

 private:
  void responder(uint8_t car, uint8_t op, protocolo::Codigo c, const char* detalle = nullptr);
  Contexto contexto() const;
  void vigilar(uint32_t ahora);
  void dibujarDepuracion();
  void enviarVida();
  void enviarRegistro();
  void leerMemoria();
  void guardarAjustes();
  void leerAjustes();
  void enviarConfig();
  void notificarEstadoSiCambio();
  void leerIdentidad();
  void guardarClaves();
  void armarQr();
  void dibujarPantalla(uint32_t ahora);
  void aplicarLista(uint32_t ahora);
  int largoLista() const;
  ElementoLista elementoLista(int i) const;
  void botonBroche(bool apretado, uint32_t ahora);
  void bleImagen(uint8_t op, const uint8_t* d, size_t n);
  void procesar(uint8_t car, const uint8_t* d, size_t n);
  void comandoRed(uint8_t op, const uint8_t* d, size_t n);
  void ota(uint8_t op, const uint8_t* d, size_t n);
  void enviarImagen(int espacio);
  // Manda por donde llegó el pedido (BLE o nube).
  void enviar(uint8_t car, const uint8_t* b, size_t n);
  size_t tamanoTrozo() const;
  void elegirAnimacion(uint32_t ahora);
  void leerRed();
  void cargarGuardada();
  size_t leerGuardada(char* buf) const;
  void leerImagenes();
  void guardarImagenes();
  // Los sprites (espacios 8 a 19 de la característica Imagen).
  void leerSprites();
  void guardarSprites();
  bool spriteValido(const char* clave, const char** porQue);
  // Cambiaron la config o los sprites: qué caras de imagen se pueden mostrar.
  void actualizarSprites();
  uint32_t firmaSprites(int cara) const;
  void avanzarSprites(uint32_t dt);
  static int leerSprite(void* contexto, int sprite, uint32_t desplazamiento, uint8_t* destino, size_t n);
  int imagenParaMostrar(uint32_t ahora);
  bool dibujarImagen(int espacio, float alfa = 1);
  void avanzarProtector(uint32_t ahora, uint32_t dt);
  void actividad() { ultimaActividad_ = hal_.ahoraMs(); }
  bool leerArchivo(const char* clave, uint32_t desplazamiento, uint8_t* destino, size_t n);
  bool imagenValida(const char* clave, uint32_t largo, const char** porQue);
  bool prepararImagen(int espacio, uint32_t ahora);
  bool cargarCuadro(int espacio, int cuadro, uint32_t ahora);
  static int leerParaQoi(void* contexto, uint32_t desplazamiento, uint8_t* destino, size_t n);
  bool bloqueado(uint32_t ahora) const;
  void sonar(const char* nombre);
  // dato >= 0: además, una entrada de tipo 4 (recordatorio) con ese índice.
  // Con tipo >= 0, además una entrada de registro de ese tipo y dato (4
  // recordatorio con su índice, 5 juego, 6 ánimo).
  void notificarEvento(Evento e, int tipo = -1, uint8_t dato = 0);
  void revisarRecordatorios(uint32_t ahora);
  void mostrarRecordatorio(int i, uint32_t ahora);
  void cerrarRecordatorio();
  void avanzarPanel(uint32_t ahora, uint32_t dt);
  void avanzarPomodoro(uint32_t ahora, uint32_t dt);
  void reiniciarPomodoro();
  void dibujarPanel();
  const char* nombrePomodoro() const;
  void falla(uint32_t ahora);
  void revisarDespertador(uint32_t ahora);
  void cuidar(uint32_t ahora);
  void preguntarAnimo(uint32_t ahora);
  void tactoJuego(bool apretado, uint32_t ahora);
  void avanzarJuego(uint32_t ahora);
  void terminarJuego(int resultado);  // 0 perdió el dueño, 1 ganó, 2 empate, 3 sin resultado
  void dibujarJuego(float cx, float W, float H, float alfa);
  void avanzarAlarma(uint32_t ahora);
  void mostrarGlobo(uint32_t ahora);
  void dibujarClima(float cx, float W, float H, float alfa);
  void log(const char* m) {
    if (hal_.registrar) hal_.registrar(m);
  }

  Hal hal_;
  Perfil perfil_;
  Lienzo lienzo_;
  Vista vista_{};
  VistaRostro vistaRostro_{};
  uint32_t horaRef_ = 0, horaRefMs_ = 0;  // la hora que mandó la app
  bool depurar_ = false;
  uint32_t ultimoCuadro_ = 0;
  float fps_ = 0;
  int ultimaBateria_ = -1, ultimoCargando_ = -1;
  uint32_t sinWifiDesde_ = 0;
  bool avisoSinWifi_ = false;
  Config config_;
  MotorVida motor_;
  Gestos gestos_;
  protocolo::Receptor receptor_;

  char nombre_[LARGO_NOMBRE] = {};       // nombre puesto por comando (pisa al de la config)
  char fijaGuardada_[LARGO_NOMBRE] = {}; // expresión fija guardada
  char serie_[13] = {};
  char id_[13] = {};
  char codigo_[7] = {};
  char qr_[40] = {};
  uint8_t claves_[4][16] = {};
  uint8_t nClaves_ = 0;
  bool emparejando_ = false;
  uint32_t emparejarHasta_ = 0;  // 0 = hasta que se vincule
  bool autenticado_ = false;
  bool vistaPrevia_ = false;
  uint8_t fallos_ = 0;
  uint32_t bloqueoHasta_ = 0;

  // Lista y pulsador del broche.
  uint8_t posLista_ = 0;
  uint32_t ultimaRotacion_ = 0;
  bool apagado_ = false;
  bool botonApretado_ = false;
  bool ignorarSoltar_ = false;
  bool qrPorBoton_ = false;
  uint32_t botonDesde_ = 0;

  // Imágenes.
  struct MetaImagen {
    uint32_t largo = 0, crc = 0;
  } imagenes_[MAX_IMAGENES], sprites_[MAX_SPRITES];
  MetaImagen* meta(int espacio);  // de una imagen (0-7) o un sprite (8-19)
  // La cara de imagen: sus sprites decodificados, de qué son (una firma de la
  // cara y de los CRC de sus sprites) y el fundido con la SDF.
  CacheSprites cache_;
  uint32_t firmaCache_ = 0;
  float opSprites_ = 0, ocultarOjos_ = 0;
  int subiendo_ = -1;  // espacio que se está recibiendo
  uint32_t subidaLargo_ = 0, subidaCrc_ = 0, subidaRecibido_ = 0, subidaCrcAcum_ = 0;
  int mostrandoImagen_ = -1;
  bool imagenSucia_ = true;
  int imagenLeyendo_ = -1;
  // La imagen que se ve, si es animada: qué cuadro va, cuándo pasa al
  // siguiente y desde dónde se lee el cuadro (0 en una imagen suelta).
  int imagenPreparada_ = -1;
  uint8_t animCuadros_ = 0, animCuadro_ = 0;
  uint32_t animProximo_ = 0, baseImagen_ = 0;
  uint32_t proximaVueltaCara_ = 0, vueltaCaraHasta_ = 0;
  Azar azar_;
  DecodificadorQoi qoi_;

  // Por dónde llegó lo que se está atendiendo.
  enum class Canal : uint8_t { Ble, Nube } canal_ = Canal::Ble;
  bool wifi_ = false, nube_ = false, redConfigurada_ = false;
  enum class Ota : uint8_t { Ninguna, Subida, Descarga } ota_ = Ota::Ninguna;
  uint32_t otaTamano_ = 0, otaRecibido_ = 0;
  uint8_t otaPorcentaje_ = 0;
  uint32_t crcConfig_ = 0;
  uint32_t arranque_ = 0;

  // Animaciones: la pedida (por comando o regla) gana sobre la de la lista.
  int animPedida_ = -1;
  bool animUnaVez_ = false;
  uint32_t animDesde_ = 0, animListaDesde_ = 0;
  int animVisible_ = -1;
  uint32_t animT_ = 0;
  char visible_[LARGO_NOMBRE + 12] = {};

  // Recordatorios, reloj y pomodoro (el panel).
  Panel panel_ = Panel::Ninguno;   // lo que se dibuja en el panel
  float fasePanel_ = 0;
  int8_t recVisible_ = -1;
  uint32_t recDesde_ = 0;
  uint16_t recPendientes_ = 0;     // bits: los que vencieron mientras se veía otro
  uint16_t recDia_[MAX_RECORDATORIOS] = {};  // día (epoch / 86400 + 1) del último disparo
  int16_t recMinuto_ = -1;         // el último minuto del día revisado
  char recTexto_[LARGO_RECORDATORIO] = {};  // copia: sigue el fundido aunque cambie la config
  char recNombre_[16] = {};        // "recordatorio:<n>", la expresión visible del estado
  bool tragarSoltar_ = false;      // el toque que cerró un recordatorio no hace nada más
  uint32_t caraHasta_ = 0;         // reloj: hasta cuándo se ve la cara por un toque
  bool pomoCorriendo_ = false, pomoDescanso_ = false;
  uint32_t pomoRestanteMs_ = 0;
  // El globo (lo que dice), el despertador y el clima.
  char globoTexto_[LARGO_TEXTO_AJUSTADO] = {};  // también el del despertador (no se ven a la vez)
  char globoPendiente_[LARGO_TEXTO_AJUSTADO] = {};
  Config::Cara caraPendiente_;
  bool hayPendiente_ = false, globo_ = false, pendienteHablando_ = false;
  uint32_t globoHasta_ = 0;
  Hablador hablador_;
  bool alarma_ = false, alarmaApretado_ = false, tragarAlarma_ = false;
  uint32_t alarmaDesde_ = 0, alarmaTono_ = 0, alarmaToque_ = 0, pospuestaHasta_ = 0;
  int16_t alarmaMinuto_ = -1;
  uint16_t alarmaDia_ = 0;
  DatosClima clima_;
  uint32_t proximaCaraClima_ = 0;
  // Cuidarte (v1.7).
  uint32_t proximaAgua_ = 0;
  bool pausaDicha_ = false;
  uint16_t animoDia_ = 0;
  bool preguntando_ = false, pregApretado_ = false, tragarPregunta_ = false;
  uint8_t pregToques_ = 0;
  uint32_t pregDesde_ = 0, pregToque_ = 0;
  // Juegos (v1.7).
  Juego juego_ = Juego::Ninguno;
  uint8_t juegoFase_ = 0, juegoRonda_ = 0, juegoPuntos_ = 0, juegoDato_ = 0;
  int8_t juegoLado_ = 0;
  uint32_t juegoDesde_ = 0, juegoProximo_ = 0, juegoAccion_ = 0;
  bool juegoApretado_ = false;
  char juegoTexto_[40] = {};
  // Protector de pantalla.
  uint32_t ultimaActividad_ = 0;
  float faseProtector_ = 0;

  uint8_t ultimoEstado_[protocolo::MAX_ESTADO] = {};
  size_t largoUltimoEstado_ = 0;
};

}  // namespace sintetica
