---
title: WhatsApp
---

El servicio `whatsmeow` conecta a Caseo el número de WhatsApp de cada gestor como si fuera un dispositivo vinculado más (igual que WhatsApp Web). Cada gestor vincula su propio número y solo ve sus conversaciones.

:::danger
**whatsmeow no es un cliente oficial de WhatsApp.** Usarlo va contra las condiciones de servicio de WhatsApp, que puede **banear el número vinculado** sin aviso. El riesgo es de quien despliega Caseo, y no hay garantía ni reembolso por ello. Para reducirlo:
- Usa un número con antigüedad y uso normal, no uno recién dado de alta.
- No lo uses con tu número personal o principal hasta haberlo probado.
- No envíes mensajes masivos ni a contactos que no te hayan escrito antes. Caseo solo deja escribir a quien te haya escrito o sea uno de tus interesados.
:::

## Vincular el número

Cada gestor lo hace desde Caseo, en **WhatsApp → Vincular número**:

1. Pulsa **Vincular número**. Caseo muestra un código QR que se renueva cada pocos segundos.
2. En el móvil, abre **WhatsApp → Dispositivos vinculados → Vincular un dispositivo** y escanea el código.
3. Al cabo de unos segundos, Caseo muestra el número como vinculado.

Para desvincularlo, pulsa **Desvincular** en la misma pantalla o cierra la sesión desde el móvil (**Dispositivos vinculados → Cerrar sesión**). Las conversaciones guardadas en Caseo se mantienen.

:::note[Instalaciones anteriores]
Si vinculaste un número con una versión anterior del conector (una sola sesión para toda la instalación), vuelve a vincularlo desde Caseo: cada gestor tiene ahora su propia sesión.
:::

## Límites de envío

El conector espacia los mensajes de cada número con un retardo aleatorio y limita cuántos salen por hora, para que el ritmo se parezca al de una persona. Los valores por defecto se pueden cambiar en `.env`:

| Variable | Por defecto | Qué hace |
|---|---|---|
| `SEND_MAX_PER_HOUR` | `60` | Mensajes por número y hora. Al superarlo, Caseo avisa de que hay que esperar. |
| `SEND_DELAY_MIN_MS` | `1500` | Retardo mínimo antes de cada envío, en milisegundos. |
| `SEND_DELAY_MAX_MS` | `4000` | Retardo máximo antes de cada envío, en milisegundos. |

Subirlos aumenta el riesgo de baneo.

## Mensajes entrantes

El conector reenvía cada mensaje de un chat individual a `core` por la red interna de Docker (`http://core:4000/api/whatsapp/whatsmeow`), con la cabecera `Authorization: Bearer $WHATSMEOW_TOKEN`. Los grupos y los estados se ignoran. Solo cambia `WHATSMEOW_WEBHOOK_URL` si `core` no está en el mismo Compose.

Si `core` no responde en ese momento, el mensaje no se guarda en Caseo, aunque sigue en el móvil.

## API del conector

Solo accesible desde la red interna de Docker. Todas las rutas salvo `/health` requieren la cabecera `Authorization: Bearer $WHATSMEOW_TOKEN`. `{id}` es la sesión de cada gestor, que asigna Caseo.

| Método y ruta | Descripción |
|---|---|
| `GET /health` | `200` si el proceso está vivo. |
| `POST /sessions/{id}/connect` | Crea la sesión si no existe y empieza la vinculación. Responde como `/status`. |
| `GET /sessions/{id}/status` | `{"connected": bool, "logged_in": bool, "jid": "34600111222"}` |
| `GET /sessions/{id}/qr` | `{"code": "..."}` mientras se espera la vinculación; `204` si no hay código. |
| `GET /sessions/{id}/qr.png` | El mismo código como imagen PNG. |
| `POST /sessions/{id}/send` | Cuerpo `{"to": "34600111222", "text": "Hola"}`. Número en formato internacional, sin `+`. `429` si se supera el límite por hora. |
| `POST /sessions/{id}/logout` | Desvincula el número y borra la sesión. |

## Dónde se guarda la sesión

Las sesiones se guardan en PostgreSQL, en las tablas `whatsmeow_*` y `caseo_whatsmeow_sessions` de la base de datos `caseo`. Las [Copias de seguridad](/copias-de-seguridad/) de la base de datos las incluyen; al restaurarlas no hace falta volver a vincular.
