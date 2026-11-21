defmodule CaseoWeb.WhatsappQrController do
  @moduledoc "Serves the owner's WhatsApp linking QR code."

  use CaseoWeb, :controller

  def show(conn, _params) do
    case Caseo.Whatsapp.qr_image(conn.assigns.current_scope) do
      {:ok, png} ->
        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", "private, no-store")
        |> send_resp(200, png)

      _none_or_error ->
        send_resp(conn, 204, "")
    end
  end
end
