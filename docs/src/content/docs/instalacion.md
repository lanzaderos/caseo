---
title: Instalación
---

## 1. Descargar los ficheros

```sh
mkdir caseo && cd caseo
curl -fsSLo compose.yaml https://raw.githubusercontent.com/lanzaderos/caseo/main/compose.prod.yaml
curl -fsSLo .env https://raw.githubusercontent.com/lanzaderos/caseo/main/.env.example
```

## 2. Configurar `.env`

Genera los secretos y escríbelos en `.env`:

```sh
sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|^WHATSMEOW_TOKEN=.*|WHATSMEOW_TOKEN=$(openssl rand -hex 32)|" .env
chmod 600 .env
```

Edita `.env` y pon tu dominio en `PHX_HOST` (sin `https://`):

```sh
PHX_HOST=caseo.tudominio.com
```

| Variable | Obligatoria | Descripción |
|---|---|---|
| `PHX_HOST` | Sí | Dominio público de Caseo. |
| `SECRET_KEY_BASE` | Sí | Clave para firmar cookies y cifrar los secretos de doble factor (TOTP). No la cambies una vez en uso: se cerrarán todas las sesiones y los usuarios con TOTP tendrán que entrar con un código de recuperación y volver a configurarlo. |
| `POSTGRES_PASSWORD` | Sí | Contraseña de PostgreSQL. Fíjala antes del primer arranque: cambiarla después requiere cambiarla también dentro de la base de datos. |
| `WHATSMEOW_TOKEN` | Sí | Token compartido entre `core` y el conector de WhatsApp. |
| `CASEO_VERSION` | No | Tag de las imágenes. Por defecto `latest`. Fija una versión (`1.2.0`) para controlar las actualizaciones. |
| `CASEO_BIND` / `CASEO_PORT` | No | Dirección y puerto donde escucha `core` en el host. Por defecto `127.0.0.1:4000`. |
| `WHATSMEOW_WEBHOOK_URL` | No | URL a la que el conector reenvía los mensajes entrantes. |

## 3. Arrancar

```sh
docker compose up -d
docker compose ps
docker compose logs -f core
```

Cuando en los logs aparezca `Running CaseoWeb.Endpoint`, Caseo está listo en `http://127.0.0.1:4000`. Las migraciones de base de datos se aplican solas en cada arranque.

Para servirlo en tu dominio con HTTPS, sigue con [HTTPS y proxy inverso](/https/).

## Limitaciones actuales

- **Correo:** el envío de correo (enlaces de acceso y confirmación) aún no se puede configurar en producción. Hasta que se resuelva [#5](https://github.com/lanzaderos/caseo/issues/5), el registro y el acceso por enlace mágico no funcionarán en una instalación self-hosted.

## Problemas frecuentes

- **`required variable ... is missing a value`**: falta una variable obligatoria en `.env`.
- **La página carga pero no reacciona a los clics**: accedes por una URL distinta de `https://PHX_HOST`. Caseo rechaza las conexiones en vivo (LiveView) desde otros orígenes; accede siempre por el dominio configurado.
