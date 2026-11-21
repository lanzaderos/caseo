---
title: Actualizaciones
---

Haz una [copia de seguridad](/copias-de-seguridad/) antes de actualizar.

```sh
docker compose pull
docker compose up -d
docker compose logs -f core
```

`core` aplica las migraciones pendientes al arrancar, así que no hay pasos manuales. Verás `Migrated ...` o `Migrations already up` en los logs.

## Versiones

- Con `CASEO_VERSION=latest` (por defecto), `docker compose pull` trae siempre la última versión publicada.
- Para controlar cuándo actualizas, fija una versión en `.env`, por ejemplo `CASEO_VERSION=1.2.0`, y cámbiala cuando quieras actualizar. Las versiones publicadas están en [Releases](https://github.com/lanzaderos/caseo/releases).

## Volver a una versión anterior

Las migraciones no se deshacen solas. Para volver atrás, restaura la copia de seguridad hecha antes de actualizar y fija la versión anterior en `CASEO_VERSION`.

## Actualizar PostgreSQL

La imagen de `db` fija la versión mayor de PostgreSQL. Cambiar de versión mayor (por ejemplo de 18 a 19) requiere exportar e importar los datos: haz un volcado con `pg_dump`, crea un volumen nuevo con la versión nueva y restaura en él (ver [Copias de seguridad](/copias-de-seguridad/)).
