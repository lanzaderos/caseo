---
title: Caseo self-hosted
---

Caseo se puede instalar gratis en tu propio servidor con Docker Compose. La instalación levanta tres contenedores:

| Servicio | Imagen | Función |
|---|---|---|
| `core` | `ghcr.io/lanzaderos/caseo` | La aplicación web (Phoenix). Aplica las migraciones al arrancar. |
| `db` | `postgres:18.7-alpine` | Base de datos PostgreSQL. Guarda los datos de Caseo y la sesión de WhatsApp. |
| `whatsmeow` | `ghcr.io/lanzaderos/caseo-whatsmeow` | Conector de WhatsApp. Solo es accesible desde la red interna. |

## Guía

1. [Requisitos](/requisitos/)
2. [Instalación](/instalacion/)
3. [HTTPS y proxy inverso](/https/)
4. [WhatsApp](/whatsapp/)
5. [Actualizaciones](/actualizaciones/)
6. [Copias de seguridad](/copias-de-seguridad/)

:::caution
El conector de WhatsApp usa [whatsmeow](https://github.com/tulir/whatsmeow), un cliente **no oficial**. WhatsApp puede banear el número vinculado. Lee [WhatsApp](/whatsapp/) antes de vincular un número.
:::
