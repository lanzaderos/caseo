defmodule CaseoWeb.ExtensionApiController do
  use CaseoWeb, :controller

  alias Caseo.Accounts
  alias Caseo.Properties

  def me(conn, _params) do
    json(conn, %{email: conn.assigns.current_scope.user.email})
  end

  def import_listing(conn, params) do
    attrs = Map.take(params, ["listing_url", "name", "rent", "location", "area_m2"])

    case Properties.import_listing(conn.assigns.current_scope, attrs) do
      {:ok, property, result} ->
        conn
        |> put_status(if(result == :created, do: :created, else: :ok))
        |> json(%{
          id: property.id,
          result: result,
          name: property.name,
          url: url(~p"/inmuebles/#{property.id}/editar")
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          errors:
            Ecto.Changeset.traverse_errors(changeset, &CaseoWeb.CoreComponents.translate_error/1)
        })
    end
  end

  def disconnect(conn, _params) do
    Accounts.delete_extension_token(conn.assigns.extension_token)
    send_resp(conn, :no_content, "")
  end
end
