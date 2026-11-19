defmodule Caseo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CaseoWeb.Telemetry,
      Caseo.Repo,
      {DNSCluster, query: Application.get_env(:caseo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Caseo.PubSub},
      # Start a worker by calling: Caseo.Worker.start_link(arg)
      # {Caseo.Worker, arg},
      # Start to serve requests, typically the last entry
      CaseoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Caseo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CaseoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
