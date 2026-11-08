/* API en C del núcleo de SintéticaOS, para las apps (Swift la importa con un
 * module map; Kotlin, por JNI) y cualquier otro anfitrión.
 *
 * Hay UNA instancia por proceso: el núcleo usa memoria estática. Todas las
 * funciones se llaman desde el mismo hilo.
 *
 * Dos usos:
 *  - Vista previa idéntica: sintetica_iniciar + sintetica_vista_previa, se le
 *    manda la config del bicho (protocolo Config) y la expresión, y se dibuja
 *    con sintetica_tick. La geometría es la misma que en la placa; el ancho
 *    puede ser el doble (640 × 344) para que se vea nítido en el celu.
 *  - Bicho virtual ("probar sin bicho"): lo mismo, pero la app le habla con los
 *    bytes del protocolo (sintetica_ble_escribir) y recibe las notificaciones
 *    por hal.notificar, como si fuera BLE.
 */
#ifndef SINTETICA_C_H
#define SINTETICA_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Una actualización firmada (ver docs/protocolo-ble.md, "OTA"). */
typedef struct sintetica_manifiesto {
  uint32_t tamano;
  uint8_t sha256[32];
  uint8_t firma[64]; /* ECDSA P-256, r || s */
  char version[24];
  char perfil[24];
} sintetica_manifiesto;

typedef struct sintetica_hal {
  void* contexto; /* se pasa tal cual a cada función */
  uint32_t (*ahora_ms)(void* contexto);
  uint32_t (*semilla)(void* contexto);
  int (*minuto_del_dia)(void* contexto); /* -1 si no se sabe */
  int (*bateria)(void* contexto);        /* 0-100, -1 si no hay */
  int (*guardar)(void* contexto, const char* clave, const uint8_t* datos, size_t n); /* 1 = ok */
  int (*leer)(void* contexto, const char* clave, uint8_t* datos, size_t cap);        /* -1 si no está */
  void (*notificar)(void* contexto, int caracteristica, const uint8_t* datos, size_t n);
  void (*registrar)(void* contexto, const char* mensaje);
  const char* identificador; /* 12 caracteres hexadecimales; NULL = "000000000000" */
  /* v1.3: nube y OTA (todo opcional). */
  void (*notificar_nube)(void* contexto, int caracteristica, const uint8_t* datos, size_t n);
  void (*red_cambio)(void* contexto);
  int (*ota_empezar)(void* contexto, const sintetica_manifiesto* m);  /* devuelven un código del protocolo */
  int (*ota_escribir)(void* contexto, uint32_t desplazamiento, const uint8_t* datos, size_t n);
  int (*ota_terminar)(void* contexto);
  int (*ota_descargar)(void* contexto, const sintetica_manifiesto* m, const char* url);
  void (*ota_cancelar)(void* contexto);
  const char* perfil;  /* "dev-147b", "broche-c3", "virtual"…; NULL = "sim" */
  const char* version; /* del firmware; NULL = la del núcleo */
  /* Archivos grandes (imágenes) por partes; NULL = en memoria, dentro de la API. */
  int (*escribir_trozo)(void* contexto, const char* clave, uint32_t desplazamiento, const uint8_t* datos, size_t n);
  int (*leer_trozo)(void* contexto, const char* clave, uint32_t desplazamiento, uint8_t* datos, size_t n);
  int (*borrar)(void* contexto, const char* clave);
  /* Segundos desde 1970 en hora local (0 = no se sabe): la memoria del motor de vida
   * (ausencias, días juntos, cumpleaños). NULL = solo el minuto del día. */
  uint32_t (*epoch)(void* contexto);
} sintetica_hal;

/* Arranca el núcleo. ancho ≤ 640, alto ≤ 640. Cualquier función de la tabla puede ser NULL.
 * Las imágenes (protocolo Imagen) se guardan en memoria, dentro de la API. */
void sintetica_iniciar(const sintetica_hal* hal, int ancho, int alto);
/* Igual, para una pantalla redonda (el broche) o con su pulsador (boton_broche = 1). */
void sintetica_iniciar_perfil(const sintetica_hal* hal, int ancho, int alto, int redonda, int boton_broche);
void sintetica_vista_previa(void);

void sintetica_tick(void);
const uint16_t* sintetica_pixeles(void); /* RGB565, ancho × alto, fila por fila */
int sintetica_ancho(void);
int sintetica_alto(void);
/* Convierte el último cuadro a RGBA de 8 bits (ancho × alto × 4 bytes). */
void sintetica_pixeles_rgba(uint8_t* salida);

void sintetica_tacto(int apretado);
void sintetica_imu(float ax, float ay, float az);
void sintetica_evento(int evento);

void sintetica_ble_conexion(int conectado);
void sintetica_ble_escribir(int caracteristica, const uint8_t* datos, size_t n);
size_t sintetica_ble_estado(uint8_t* salida, size_t cap);

/* Lo que llega por la nube (MQTT): [característica][datos] ya separados. */
void sintetica_nube_escribir(int caracteristica, const uint8_t* datos, size_t n);
void sintetica_conexiones(int wifi, int nube);
/* Las credenciales guardadas; 1 si hay. */
int sintetica_red(char* ssid, size_t cap_ssid, char* clave, size_t cap_clave);
int sintetica_nube(char* url, size_t cap_url, char* usuario, size_t cap_usuario, char* clave, size_t cap_clave);
void sintetica_ota_progreso(int codigo, int porcentaje, const char* detalle);
uint32_t sintetica_crc_config(void);
/* El texto que se firma para una OTA. Devuelve el largo (0 si no entra). */
size_t sintetica_mensaje_ota(const sintetica_manifiesto* m, char* salida, size_t cap);

/* Lo que se ve en el broche dormido: 1 = la pantalla apagada (quiere dormir). */
int sintetica_quiere_dormir(void);

/* Valida una config de usuario (sin tocar la instancia). 0 = válida; si no,
 * el código de error y el detalle en `detalle`. No hace falta haber llamado a
 * sintetica_iniciar. */
int sintetica_validar_config(const char* json, size_t n, char* detalle, size_t cap);

/* Dibuja una expresión paramétrica (del motor de vida) como la ve el editor,
 * sin tocar la instancia: la de la config `json` (n bytes; NULL o n = 0 = solo
 * las de fábrica) que se llama `nombre`, en el instante `t` (segundos: fases
 * del giro, el latido, el brillo), con una partícula de muestra si la cara
 * suelta alguna. `rgba` recibe ancho × alto × 4 bytes (ancho y alto de 16 a 640).
 * Devuelve 0 si la dibujó; -1 si no hay una expresión paramétrica con ese
 * nombre; > 0 si la config no es válida (el código, con el detalle en `detalle`).
 * No hace falta haber llamado a sintetica_iniciar. */
int sintetica_dibujar_expresion(const char* json, size_t n, const char* nombre, int ancho, int alto, int redonda,
                                float t, uint8_t* rgba, char* detalle, size_t cap);

/* Como sintetica_dibujar_expresion, con un parpadeo: `cierre` de 0 (abierto) a
 * 1 (cerrado). Una cara de imagen ("sprites") se dibuja con los sprites
 * sueltos (sintetica_sprite_suelto); si no está el de su ojo, con la SDF. */
int sintetica_dibujar_expresion_cierre(const char* json, size_t n, const char* nombre, int ancho, int alto, int redonda,
                                       float t, float cierre, uint8_t* rgba, char* detalle, size_t cap);

/* Los sprites que usa sintetica_dibujar_expresion (aparte de los del bicho de
 * la instancia): `sprite` de 0 a 11, un QOI de 3 o 4 canales de hasta
 * 128 × 128. n = 0 lo borra. Devuelve 0 si lo guardó, -1 si no es válido. */
int sintetica_sprite_suelto(int sprite, const uint8_t* qoi, size_t n);

/* Lo de fábrica del motor de vida (shared/formato/vida): tipo 0 = las
 * expresiones paramétricas, 1 = los comportamientos. Devuelve cuántos hay; si
 * `indice` está en rango, deja en *nombre y *json los de ese (el JSON, como en
 * la config). */
int sintetica_vida_base(int tipo, int indice, const char** nombre, const char** json);

int sintetica_cantidad_expresiones(void);
const char* sintetica_nombre_expresion(int indice);
/* La expresión visible, o "animacion:<nombre>" mientras se ve una animación. */
const char* sintetica_expresion_visible(void);
const char* sintetica_qr(void);
/* La imagen que se ve (-1 = una cara). */
int sintetica_imagen_visible(void);
const char* sintetica_version(void);

#ifdef __cplusplus
}
#endif

#endif
