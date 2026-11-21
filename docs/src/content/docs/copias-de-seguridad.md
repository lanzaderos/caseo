---
title: Copias de seguridad
---

Todos los datos de Caseo, incluida la sesión de WhatsApp, están en PostgreSQL. Una copia de la base de datos y del fichero `.env` es suficiente para restaurar la instalación.

## Hacer una copia

```sh
docker compose exec -T db pg_dump -U caseo -Fc caseo > caseo-$(date +%F).dump
cp .env env-backup
```

Guarda las copias **fuera del servidor** (otro servidor, almacenamiento de objetos…). El `.env` contiene secretos: guárdalo cifrado.

### Copia diaria automática

Ejemplo con `cron` (copia a las 3:00 y conserva 14 días):

```sh
0 3 * * * cd /ruta/a/caseo && docker compose exec -T db pg_dump -U caseo -Fc caseo > backups/caseo-$(date +\%F).dump && find backups -name 'caseo-*.dump' -mtime +14 -delete
```

## Restaurar

En una instalación nueva, con el mismo `.env`:

```sh
docker compose up -d db
docker compose exec -T db pg_restore -U caseo -d caseo --clean --if-exists < caseo-2026-11-21.dump
docker compose up -d
```

Comprueba que la aplicación arranca (`docker compose logs core`) y que `/status` del conector de WhatsApp devuelve `"logged_in": true`.
