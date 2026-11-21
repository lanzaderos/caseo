# Imagen de producción de Caseo (servicio "core").
# Versiones alineadas con .tool-versions; actualízalas juntas.
ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.0.6
ARG UBUNTU_VERSION=noble-20261110.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION} AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

FROM ubuntu:${UBUNTU_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 libsctp1 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod PHX_SERVER=true

WORKDIR /app
RUN chown nobody /app
COPY --from=build --chown=nobody:root /app/_build/prod/rel/caseo ./
USER nobody

EXPOSE 4000
# Aplica las migraciones pendientes y arranca la aplicación.
CMD ["sh", "-c", "bin/caseo eval Caseo.Release.migrate && exec bin/caseo start"]
