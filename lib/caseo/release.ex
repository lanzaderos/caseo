defmodule Caseo.Release do
  @moduledoc """
  Tareas de release que se ejecutan sin Mix, por ejemplo las migraciones
  al arrancar el contenedor: `bin/caseo eval Caseo.Release.migrate`.
  """
  @app :caseo

  def migrate do
    Application.ensure_all_started(:ssl)
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
