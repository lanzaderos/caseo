defmodule CaseoWeb.PropertyAddressController do
  use CaseoWeb, :controller

  alias Caseo.Properties.AddressSearch

  def index(conn, params) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    case AddressSearch.search(params["address_query"]) do
      {:ok, addresses} -> json(conn, %{addresses: addresses})
      {:error, :unavailable} -> conn |> put_status(:service_unavailable) |> json(%{addresses: []})
    end
  end
end
