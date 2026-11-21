defmodule CaseoWeb.ExtensionApiController do
  use CaseoWeb, :controller

  alias Caseo.Accounts
  alias Caseo.Properties.Imports

  def me(conn, _params) do
    json(conn, %{email: conn.assigns.current_scope.user.email})
  end

  @doc """
  Stores the raw listing read by the extension and returns the preview path,
  where the owner reviews it before anything is created. The extension joins
  the path to the server it is configured for.
  """
  def create_import(conn, params) do
    case Imports.create(conn.assigns.current_scope, params) do
      {:ok, listing_import} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: listing_import.id,
          preview_path: ~p"/importaciones/#{listing_import.id}"
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
