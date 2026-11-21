defmodule CaseoWeb.PropertyPhotoController do
  use CaseoWeb, :controller

  alias Caseo.Properties.Photos

  def show(conn, %{"id" => id}) do
    case Photos.fetch(conn.assigns.current_scope, id) do
      {:ok, photo} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_content_type(photo.content_type, nil)
        |> send_resp(200, photo.data)

      {:error, :not_found} ->
        send_resp(conn, 404, "")
    end
  end
end
