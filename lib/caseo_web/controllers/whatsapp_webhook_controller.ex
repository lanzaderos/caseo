defmodule CaseoWeb.WhatsappWebhookController do
  @moduledoc "Receives messages from WhatsApp providers. Each provider authenticates its own calls."

  use CaseoWeb, :controller

  alias Caseo.Whatsapp

  def create(conn, %{"provider" => provider} = params) do
    case Whatsapp.receive_event(provider, conn.req_headers, Map.delete(params, "provider")) do
      {:error, :unauthorized} -> send_resp(conn, 401, "")
      {:error, :unknown_account} -> send_resp(conn, 404, "")
      # Stored, duplicate or ignored: the provider must not retry.
      _ -> send_resp(conn, 204, "")
    end
  end
end
