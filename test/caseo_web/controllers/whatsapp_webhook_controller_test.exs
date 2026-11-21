defmodule CaseoWeb.WhatsappWebhookControllerTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Repo
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Message

  test "stores authenticated messages and rejects the rest", %{conn: conn} do
    owner = user_fixture()

    account =
      Repo.insert!(%Account{
        owner_id: owner.id,
        provider: "whatsmeow",
        session_id: "s1",
        linked_at: DateTime.utc_now(:second)
      })

    event = %{
      "session" => "s1",
      "id" => "M1",
      "chat" => "34612345678",
      "from_me" => false,
      "type" => "text",
      "text" => "Hola",
      "timestamp" => "2026-11-21T09:59:00Z"
    }

    assert conn |> post(~p"/api/whatsapp/whatsmeow", event) |> response(401)

    authed = put_req_header(build_conn(), "authorization", "Bearer test-whatsmeow-token")
    assert authed |> post(~p"/api/whatsapp/whatsmeow", event) |> response(204)
    assert [%Message{account_id: id, body: "Hola"}] = Repo.all(Message)
    assert id == account.id

    # A retry does not duplicate it.
    assert authed |> post(~p"/api/whatsapp/whatsmeow", event) |> response(204)
    assert Repo.aggregate(Message, :count) == 1

    assert authed
           |> post(~p"/api/whatsapp/whatsmeow", %{event | "session" => "x"})
           |> response(404)
  end
end
