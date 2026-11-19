defmodule Caseo.Repo do
  use Ecto.Repo,
    otp_app: :caseo,
    adapter: Ecto.Adapters.Postgres
end
