---
title: WhatsApp
---

El servicio `whatsmeow` conecta un número de WhatsApp a Caseo como si fuera un dispositivo vinculado más (igual que WhatsApp Web).

:::danger
**whatsmeow no es un cliente oficial de WhatsApp.** Usarlo va contra las condiciones de servicio de WhatsApp, que puede **banear el número vinculado** sin aviso. El riesgo es de quien despliega Caseo. Para reducirlo:
- Usa un número con antigüedad y uso normal, no uno recién dado de alta.
- No lo uses con tu número personal o principal hasta haberlo probado.
- No envíes mensajes masivos ni a contactos que no te hayan escrito antes.
:::

## Vincular el número

Hasta que la vinculación esté integrada en la interfaz de Caseo, se hace llamando al conector desde el servidor, en la carpeta de la instalación:

```sh
docker run --rm --network "$(basename "$PWD")_default" --env-file .env --entrypoint sh curlimages/curl:8.11.1 \
  -c 'curl -s -H "Authorization: Bearer $WHATSMEOW_TOKEN" http://whatsmeow:8080/qr'
```

(`$(basename "$PWD")_default` es la red que crea Docker Compose: si la carpeta se llama `caseo`, la red es `caseo_default`.)

La respuesta es `{"code":"..."}`. Convierte ese texto en un QR (por ejemplo con `qrencode -t ansiutf8 'TEXTO'`) y escanéalo desde el móvil en **WhatsApp → Dispositivos vinculados → Vincular un dispositivo**. Los códigos caducan cada pocos segundos; si falla, vuelve a pedir uno.

Cuando el número esté vinculado, `/qr` responde `204` y `/status` devuelve `"logged_in": true`.

## API del conector

Solo accesible desde la red interna de Docker. Todas las rutas salvo `/health` requieren la cabecera `Authorization: Bearer $WHATSMEOW_TOKEN`.

| Método y ruta | Descripción |
|---|---|
| `GET /health` | `200` si el proceso está vivo. |
| `GET /status` | `{"connected": bool, "logged_in": bool, "jid": "34600111222"}` |
| `GET /qr` | `{"code": "..."}` mientras se espera la vinculación; `204` si ya está vinculado. |
| `POST /send` | Cuerpo `{"to": "34600111222", "text": "Hola"}`. Número en formato internacional, sin `+` ni espacios. |
| `POST /logout` | Desvincula el número. |

Si `WHATSMEOW_WEBHOOK_URL` está definido, cada mensaje entrante se envía allí como `POST` JSON con `id`, `from`, `chat`, `push_name`, `from_me`, `text` y `timestamp`, y la misma cabecera `Authorization`.

## Desvincular o cambiar de número

Desvincula desde el móvil (**Dispositivos vinculados → Cerrar sesión**) o con `POST /logout`. El conector vuelve solo al modo de vinculación y `/qr` vuelve a dar códigos.

## Dónde se guarda la sesión

La sesión se guarda en PostgreSQL, en las tablas `whatsmeow_*` de la base de datos `caseo`. Las [Copias de seguridad](/copias-de-seguridad/) de la base de datos la incluyen; al restaurarlas no hace falta volver a vincular.
