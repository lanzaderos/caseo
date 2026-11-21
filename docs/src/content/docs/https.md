---
title: HTTPS y proxy inverso
---

`core` no gestiona certificados. Ponlo detrás de un proxy inverso que termine HTTPS. La opción más sencilla es **Caddy**, que obtiene y renueva los certificados de Let's Encrypt automáticamente.

## Caddy en el mismo `compose.yaml`

Añade este servicio a `compose.yaml`:

```yaml
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    command: caddy reverse-proxy --from ${PHX_HOST} --to core:4000
    volumes:
      - caddy_data:/data
```

Y el volumen al final del fichero, dentro de `volumes:`:

```yaml
  caddy_data:
```

Como Caddy llega a `core` por la red interna, puedes dejar de publicar el puerto de `core` en el host quitando su sección `ports:`.

Aplica los cambios:

```sh
docker compose up -d
```

En uno o dos minutos Caseo estará disponible en `https://PHX_HOST`.

## Proxy propio (Nginx, Traefik…)

Si ya tienes un proxy en el servidor, apúntalo a `127.0.0.1:4000` (o al valor de `CASEO_BIND`/`CASEO_PORT`). Ten en cuenta que:

- Debe reenviar las conexiones **WebSocket** (`Upgrade`/`Connection`), que LiveView necesita.
- El dominio con el que accedes tiene que coincidir con `PHX_HOST`.

Ejemplo mínimo para Nginx:

```nginx
location / {
    proxy_pass http://127.0.0.1:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```
