// La charla sin IA en el robot (v1.10): Sistema::charlar arma el contexto
// (la hora, el clima, los hábitos, los gustos), le pregunta al motor de
// charla (charla.cpp), hace la acción y contesta con su globo y su voz propia.
#include "sistema.h"

namespace sintetica {

namespace {
constexpr const char* CLAVE_GUSTOS = "gustos";
constexpr uint32_t CALLADO_MS = 60u * 60000u;  // "callate": una hora sin frases espontáneas
constexpr uint32_t VOZ_ADELANTO = 2400;        // muestras (150 ms) que se mandan de más

// Arma un texto de a pedazos (como el de charla.cpp).
struct Escritor {
  char* s;
  size_t cap, n = 0;
  Escritor(char* d, size_t c) : s(d), cap(c) {
    if (cap) s[0] = 0;
  }
  void texto(const char* t) {
    for (size_t i = 0; t[i] && n + 1 < cap; i++) s[n++] = t[i];
    if (cap) s[n] = 0;
  }
  void numero(int v) {
    char b[12];
    int k = 0;
    unsigned u = v < 0 ? 0u : static_cast<unsigned>(v);
    do b[k++] = static_cast<char>('0' + u % 10), u /= 10;
    while (u && k < 11);
    char c[2] = {0, 0};
    while (k) c[0] = b[--k], texto(c);
  }
};
}  // namespace

size_t Sistema::gustos(char* salida, size_t cap) const {
  if (!cap) return 0;
  salida[0] = 0;
  if (!hal_.leer) return 0;
  const int n = hal_.leer(CLAVE_GUSTOS, reinterpret_cast<uint8_t*>(salida), cap - 1);
  if (n <= 0) {
    salida[0] = 0;
    return 0;
  }
  salida[n] = 0;
  return static_cast<size_t>(n);
}

bool Sistema::charlar(const char* texto, size_t n, RespuestaCharla* r, bool siNoEntiende) {
  const uint32_t ahora = hal_.ahoraMs();
  ContextoCharla ctx;
  ctx.dueno = config_.vida.dueno;
  ctx.robot = nombre();
  ctx.preset = presetCercano(motor_.rasgos());
  ctx.minuto = minutoDelDia();
  ctx.epoch = epoch();
  char clima[40] = {};
  if (climaVigente() && textoClima(clima_, clima, sizeof clima)) ctx.clima = clima;
  for (int i = 0; i < config_.habitos.n; i++) ctx.habitos[i] = config_.habitos.lista[i].nombre;
  ctx.nHabitos = config_.habitos.n;
  char gs[LARGO_LISTA_GUSTOS + 1];
  if (gustos(gs, sizeof gs)) ctx.gustos = gs;
  ctx.diasJuntos = motor_.memoria().dias ? motor_.memoria().dias : -1;
  ctx.alarmaSonando = alarma_;
  ctx.segundos = ahora / 1000u;
  ctx.semilla = azar_.siguiente();
  sintetica::charlar(texto, n, ctx, charla_, r);
  actividad();
  motor_.interaccion(ahora);
  if (r->noEntendi && !siNoEntiende) {
    // Que conteste otro (la IA): mientras, piensa.
    motor_.reaccionar(config_.resolverCara("pensando"), ahora, 2500);
    return false;
  }
  hacerAccion(*r, ahora);
  log(r->noEntendi ? "charla: no entendí" : "charla");
  return !r->noEntendi;
}

void Sistema::hacerAccion(const RespuestaCharla& r, uint32_t ahora) {
  const EntidadesCharla& e = r.e;
  // Cuánto falta (ms) para la hora que pidió (una vez).
  auto falta = [&]() -> uint32_t {
    // Lo relativo ("en 10 minutos", "10 segundos") cuenta desde ahora: con la
    // hora del día (que también viene) daba de 0 a 59 s menos (un timer de
    // un minuto podía durar un segundo).
    if (e.enSegundos > 0) return static_cast<uint32_t>(e.enSegundos) * 1000u;
    if (e.enMinutos >= 0) return static_cast<uint32_t>(e.enMinutos) * 60000u;
    const int m = minutoDelDia();
    if (e.minuto < 0 || m < 0) return e.enMinutos >= 0 ? static_cast<uint32_t>(e.enMinutos) * 60000u : 0;
    int d = (e.dia > 0 ? e.dia : 0) * 1440 + e.minuto - m;
    if (d <= 0) d += 1440;
    const uint32_t ep = epoch();
    const int seg = ep ? static_cast<int>(ep % 60u) : 0;
    return static_cast<uint32_t>(d * 60 - seg) * 1000u;
  };
  bool conGlobo = r.frase[0] != 0;
  fraseTimer_[0] = 0;
  switch (r.accion) {
    case AccionCharla::Alarma:
      if (e.dias && e.minuto >= 0) {
        // Todos los días (o algunos): el despertador de la config (en la RAM;
        // la nube o la app lo guardan con el aviso 0xCC).
        config_.despertador.hay = config_.despertador.activo = true;
        config_.despertador.minuto = static_cast<uint16_t>(e.minuto);
        config_.despertador.dias = e.dias;
        alarmaMinuto_ = -1;
      } else if (const uint32_t ms = falta()) {
        alarmaCharlaMs_ = ahora + ms;
        if (!alarmaCharlaMs_) alarmaCharlaMs_ = 1;
      }
      break;
    case AccionCharla::CancelarAlarma:
      alarmaCharlaMs_ = 0;
      pospuestaHasta_ = 0;
      if (alarma_) apagarAlarma();
      break;
    case AccionCharla::Posponer: posponerAlarma(); break;
    case AccionCharla::ApagarAlarma: apagarAlarma(); break;
    case AccionCharla::Recordatorio:
      if (e.dias && e.minuto >= 0 && config_.nRecordatorios < MAX_RECORDATORIOS) {
        Recordatorio& x = config_.recordatorios[config_.nRecordatorios++];
        x = Recordatorio();
        x.minuto = static_cast<uint16_t>(e.minuto);
        x.dias = e.dias;
        copiarTexto(x.texto, sizeof x.texto, e.texto);
        recMinuto_ = -1;
      } else if (const uint32_t ms = falta()) {
        recCharlaMs_ = ahora + ms;
        if (!recCharlaMs_) recCharlaMs_ = 1;
        copiarTexto(recCharla_, sizeof recCharla_, e.texto);
      }
      break;
    case AccionCharla::Habito:
      if (r.dato >= 0 && r.dato < config_.habitos.n) marcarHabito(r.dato, 0, true);
      break;
    case AccionCharla::Jugar:
      if (r.dato >= 0 && r.dato <= 4) {
        jugar(static_cast<Juego>(r.dato));
        const size_t k = copiarTexto(visibleJuego_, sizeof visibleJuego_, "juego:");
        copiarTexto(visibleJuego_ + k, sizeof visibleJuego_ - k, nombreJuego(r.dato));
        conGlobo = false;  // el juego tiene su panel
      }
      break;
    case AccionCharla::Modo:
      if (r.dato >= 0 && r.dato <= 3) {
        const Modo antes = config_.modo;
        config_.modo = static_cast<Modo>(r.dato);
        if (config_.modo != antes) reiniciarPomodoro();
      }
      break;
    case AccionCharla::Gusto:
    case AccionCharla::OlvidarGusto: {
      char gs[LARGO_LISTA_GUSTOS + 1];
      gustos(gs, sizeof gs);
      const size_t k = r.accion == AccionCharla::Gusto ? sumarGusto(gs, sizeof gs, e.texto) : sacarGusto(gs, sizeof gs, e.texto);
      if (hal_.guardar) hal_.guardar(CLAVE_GUSTOS, reinterpret_cast<const uint8_t*>(gs), k);
      break;
    }
    case AccionCharla::Dormir: dormirTrasGlobo_ = true; break;
    case AccionCharla::Despertar:
      if (motor_.dormido()) motor_.despertar(ahora, false);
      break;
    case AccionCharla::Dueno: copiarTexto(config_.vida.dueno, sizeof config_.vida.dueno, e.texto); break;
    case AccionCharla::Volumen: {
      const int v = config_.voz.volumen + (r.dato > 0 ? 20 : -20);
      config_.voz.volumen = static_cast<uint8_t>(v < 10 ? 10 : v > 100 ? 100 : v);
      break;
    }
    case AccionCharla::Callar:
      calladoHasta_ = ahora + CALLADO_MS;
      if (!calladoHasta_) calladoHasta_ = 1;
      break;
    case AccionCharla::Animo:
      if (r.dato >= 0 && r.dato <= 2) {
        preguntando_ = false;
        motor_.anotarHoy(Hoy::Animo, static_cast<uint8_t>(r.dato + 1));
        motor_.anotarRegistro(6, static_cast<uint8_t>(r.dato));
        evento(Evento::Animo);
        notificarEvento(Evento::Animo, 6, static_cast<uint8_t>(r.dato));
      }
      break;
    case AccionCharla::Timer:
      if (const uint32_t ms = falta()) {
        // Un lugar libre o, si no hay, el que termina primero.
        int k = 0;
        for (int i = 0; i < MAX_TIMERS; i++) {
          if (!timers_[i].fin) {
            k = i;
            break;
          }
          if (timers_[i].fin - ahora < timers_[k].fin - ahora) k = i;
        }
        TimerCharla& t = timers_[k];
        t.fin = ahora + ms;
        if (!t.fin) t.fin = 1;
        t.total = ms;
        const char* n = e.texto;
        if (iguales(n, "para ", 5)) n += 5;  // "para los fideos" → "los fideos"
        copiarTexto(t.nombre, sizeof t.nombre, iguales(n, "\xC2\xA1Tiempo!") ? "" : n);
      }
      break;
    case AccionCharla::CancelarTimer: {
      int n = 0;
      for (TimerCharla& t : timers_)
        if (t.fin) t.fin = 0, n++;
      if (timerSonando_ >= 0) timerSonando_ = -1, n++;
      if (!n) copiarTexto(fraseTimer_, sizeof fraseTimer_, "No hay ningún timer andando.");
      break;
    }
    case AccionCharla::CuantoFalta: {
      const int k = timerMasProximo();
      if (k < 0) {
        copiarTexto(fraseTimer_, sizeof fraseTimer_, "No hay ningún timer andando.");
        break;
      }
      const uint32_t s = (timers_[k].fin - ahora + 999) / 1000u;
      Escritor x(fraseTimer_, sizeof fraseTimer_);
      x.texto("Faltan ");
      if (s >= 60) {
        x.numero(static_cast<int>(s / 60));
        x.texto(s / 60 == 1 ? " minuto" : " minutos");
        if (s % 60 && s < 600) x.texto(" y "), x.numero(static_cast<int>(s % 60)), x.texto(" segundos");
      } else {
        x.numero(static_cast<int>(s));
        x.texto(" segundos");
      }
      if (timers_[k].nombre[0]) x.texto(" para "), x.texto(timers_[k].nombre);
      x.texto(".");
      break;
    }
    case AccionCharla::Confirmar:
      if (recConfirmar_ >= 0) confirmarRecordatorio();
      break;
    case AccionCharla::ConsultarRecordatorio: {
      // "¿Tomé la pastilla?": el último recordatorio con "confirmar" de hoy.
      int k = -1;
      for (int i = 0; i < config_.nRecordatorios; i++)
        if (config_.recordatorios[i].confirmar && (k < 0 || recConfirmado_[i] > recConfirmado_[k])) k = i;
      if (k < 0) {
        copiarTexto(fraseTimer_, sizeof fraseTimer_, "No tengo nada para confirmar.");
        break;
      }
      const uint32_t ep = epoch(), hecho = recConfirmado_[k];
      Escritor x(fraseTimer_, sizeof fraseTimer_);
      if (recConfirmar_ == k) {
        x.texto("Todavía no. Es la de las ");
      } else if (hecho && ep && hecho / 86400u == ep / 86400u) {
        const int m = static_cast<int>((hecho % 86400u) / 60u);
        x.texto("Sí, la confirmaste a las ");
        x.numero(m / 60), x.texto(":"), x.texto(m % 60 < 10 ? "0" : ""), x.numero(m % 60), x.texto(".");
        break;
      } else {
        x.texto("Hoy todavía no. Es la de las ");
      }
      const int m = config_.recordatorios[k].minuto;
      x.numero(m / 60), x.texto(":"), x.texto(m % 60 < 10 ? "0" : ""), x.numero(m % 60), x.texto(".");
      break;
    }
    case AccionCharla::Emergencia:
      // El aviso a la familia lo manda la nube (con el 0xCC); acá, que se note.
      sonar("ayuda");
      break;
    default: break;  // Toque, Música: los hace la nube (con el aviso 0xCC)
  }
  if (r.comportamiento[0]) {
    const int c = config_.vida.indiceComportamiento(r.comportamiento);
    if (c >= 0) motor_.comportamiento(c, ahora);
  }
  if (conGlobo) {
    const Config::Cara cara = r.expresion[0] ? config_.resolverCara(r.expresion) : Config::Cara();
    // Lo que sabe el robot y no la charla (cuánto falta) reemplaza la frase.
    decir(fraseTimer_[0] ? fraseTimer_ : r.frase, cara, !cara.existe());
  }
}

// [0xCC][código][flags: bit 0 no entendió, bit 1 falta, bit 2 hizo una acción, bit 3 pregunta si lo hace][confianza]
// [n][intención][u8 acción][i8 dato][i16 minuto][i16 en minutos][i8 día][u8 días][n][texto][n][frase]
void Sistema::responderCharla(const RespuestaCharla& r, bool porComando) {
  using namespace protocolo;
  uint8_t b[MAX_NOTIFICACION];
  size_t i = 0;
  b[i++] = static_cast<uint8_t>(CmdCharlar | Respuesta);
  b[i++] = Ok;
  b[i++] = static_cast<uint8_t>((r.noEntendi ? 1 : 0) | (r.falta ? 2 : 0) | (r.accion != AccionCharla::Ninguna ? 4 : 0) |
                                (r.confirma ? 8 : 0));
  b[i++] = r.confianza;
  auto texto = [&](const char* s, size_t max) {
    size_t k = largo(s);
    if (k > max) k = max;
    b[i++] = static_cast<uint8_t>(k);
    copiarBytes(b + i, s, k);
    i += k;
  };
  texto(r.nombre(), 24);
  b[i++] = static_cast<uint8_t>(r.accion);
  b[i++] = static_cast<uint8_t>(r.dato);
  b[i++] = static_cast<uint8_t>(r.e.minuto), b[i++] = static_cast<uint8_t>(static_cast<uint16_t>(r.e.minuto) >> 8);
  b[i++] = static_cast<uint8_t>(r.e.enMinutos), b[i++] = static_cast<uint8_t>(static_cast<uint16_t>(r.e.enMinutos) >> 8);
  b[i++] = static_cast<uint8_t>(r.e.dia);
  b[i++] = r.e.dias;
  texto(r.e.texto, LARGO_TEXTO_CHARLA - 1);
  texto(r.frase, LARGO_FRASE - 1);
  if (porComando) {
    enviar(CarComando, b, i);
  } else {
    if (hal_.notificar) hal_.notificar(CarComando, b, i);
    if (hal_.notificarNube) hal_.notificarNube(CarComando, b, i);
  }
}

void Sistema::avisarCharla(const RespuestaCharla& r) { responderCharla(r, false); }

int Sistema::timerMasProximo() const {
  const uint32_t ahora = hal_.ahoraMs();
  int k = -1;
  for (int i = 0; i < MAX_TIMERS; i++)
    if (timers_[i].fin && (k < 0 || timers_[i].fin - ahora < timers_[k].fin - ahora)) k = i;
  return k;
}

uint32_t Sistema::faltaTimer() const {
  const int k = timerMasProximo();
  if (k < 0) return 0;
  const int32_t f = static_cast<int32_t>(timers_[k].fin - hal_.ahoraMs());
  return f > 0 ? static_cast<uint32_t>(f) : 1;
}

int Sistema::timersAndando() const {
  int n = 0;
  for (const TimerCharla& t : timers_) n += t.fin ? 1 : 0;
  return n;
}

// Un timer que terminó: lo dice y suena cada vez más fuerte hasta un toque
// (o un minuto).
void Sistema::avanzarTimers(uint32_t ahora) {
  for (int i = 0; i < MAX_TIMERS; i++) {
    TimerCharla& t = timers_[i];
    if (!t.fin || static_cast<int32_t>(ahora - t.fin) < 0) continue;
    t.fin = 0;
    timerSonando_ = static_cast<int8_t>(i);
    timerSonandoDesde_ = ahora;
    timerProximoBip_ = ahora;
    copiarTexto(nombreSonando_, sizeof nombreSonando_, t.nombre);
    if (motor_.dormido()) motor_.despertar(ahora, false);
    char f[64];
    Escritor x(f, sizeof f);
    x.texto("\xC2\xA1Tiempo!");
    if (t.nombre[0]) x.texto(" "), x.texto(t.nombre), x.texto(".");
    decir(f, config_.resolverCara("sorpresa"));
    evento(Evento::Recordatorio);
    log("terminó un timer");
  }
  if (timerSonando_ < 0) return;
  if (ahora - timerSonandoDesde_ >= 60000u) {
    timerSonando_ = -1;
    return;
  }
  if (static_cast<int32_t>(ahora - timerProximoBip_) >= 0) {
    timerProximoBip_ = ahora + 1500;
    char s[16] = "despertador:1";
    s[12] = static_cast<char>('0' + mini(5, 1 + static_cast<int>((ahora - timerSonandoDesde_) / 10000u)));
    sonar(s);
  }
}

void Sistema::revisarCharla(uint32_t ahora) {
  avanzarTimers(ahora);
  if (alarmaCharlaMs_ && !alarma_ && static_cast<int32_t>(ahora - alarmaCharlaMs_) >= 0) {
    alarmaCharlaMs_ = 0;
    sonarAlarma(true);
  }
  if (recCharlaMs_ && static_cast<int32_t>(ahora - recCharlaMs_) >= 0) {
    recCharlaMs_ = 0;
    if (motor_.dormido()) motor_.despertar(ahora, false);
    sonar("recordatorio");
    evento(Evento::Recordatorio);
    // En el panel del recordatorio, como los de la config (con "Ya está" y
    // "Después" en el cubito): un recordatorio de la charla no tiene índice.
    if (recVisible_ < 0) {
      recVisible_ = REC_CHARLA;
      recDesde_ = ahora;
      copiarTexto(recTexto_, sizeof recTexto_, recCharla_[0] ? recCharla_ : "\xC2\xA1Tiempo!");
      copiarTexto(recNombre_, sizeof recNombre_, "recordatorio:charla");
      motor_.reaccionar(config_.resolverCara("sorpresa"), ahora, 1500);
    } else {
      decir(recCharla_[0] ? recCharla_ : "\xC2\xA1Tiempo!", config_.resolverCara("sorpresa"));
    }
    log("recordatorio de la charla");
  }
  // "Andá a dormir": cuando se va el globo de las buenas noches.
  if (dormirTrasGlobo_ && !globo_ && !hayPendiente_) {
    dormirTrasGlobo_ = false;
    if (!motor_.dormido()) motor_.siesta(ahora, 20u * 60u);
  }
}

void Sistema::avanzarVoz(uint32_t ahora) {
  if (!voz_.hablando()) {
    vozSuelta_ = false;
    return;
  }
  // Si el globo se fue (un toque, otro globo), se calla (una vocalización
  // sin globo sigue hasta el final).
  if ((!globo_ && !vozSuelta_) || !hal_.audio || !vozModo_) {
    voz_.parar();
    vozSuelta_ = false;
    return;
  }
  const uint32_t objetivo = (ahora - vozDesde_) * (MUESTRAS_POR_SEGUNDO_VOZ / 1000) + VOZ_ADELANTO;
  int16_t b[256];
  while (vozEnviadas_ < objetivo && voz_.hablando()) {
    const uint32_t quiero = objetivo - vozEnviadas_;
    const size_t k = voz_.generar(b, quiero < 256 ? quiero : 256);
    if (k) hal_.audio(b, k);
    vozEnviadas_ += static_cast<uint32_t>(k);
    if (!k) break;
  }
}

}  // namespace sintetica
