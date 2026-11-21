---
title: Requisitos
---

- Un servidor Linux con **al menos 1 GB de RAM** (2 GB recomendados) y 10 GB de disco.
- **Docker** 24 o superior con el plugin **Docker Compose** v2 (`docker compose version`).
- Un **dominio** (por ejemplo `caseo.tudominio.com`) con un registro DNS `A`/`AAAA` apuntando al servidor.
- Los puertos **80 y 443** abiertos hacia Internet para el proxy inverso con HTTPS.
- `openssl` para generar los secretos.

Caseo no necesita más puertos abiertos: `core` escucha por defecto solo en `127.0.0.1:4000`, y `db` y `whatsmeow` solo en la red interna de Docker.

Siguiente paso: [Instalación](/instalacion/).
