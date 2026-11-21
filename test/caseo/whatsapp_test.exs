defmodule Caseo.WhatsappTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Leads
  alias Caseo.Repo
  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Message
  alias Caseo.Whatsapp.Whatsmeow

  @auth [{"authorization", "Bearer test-whatsmeow-token"}]

  setup do
    scope = user_scope_fixture()
    %{scope: scope}
  end

  test "links the owner's number through their own sidecar session", %{scope: scope} do
    test_pid = self()

    Req.Test.stub(Whatsmeow, fn conn ->
      send(
        test_pid,
        {:sidecar, conn.method, conn.request_path,
         Plug.Conn.get_req_header(conn, "authorization")}
      )

      case conn.request_path |> String.split("/") |> List.last() do
        "connect" -> Req.Test.json(conn, %{connected: true, logged_in: false, jid: ""})
        "status" -> Req.Test.json(conn, %{connected: true, logged_in: true, jid: "34600111222"})
      end
    end)

    {:ok, account} = Whatsapp.connect(scope)
    assert account.provider == "whatsmeow"
    assert account.owner_id == scope.user.id
    refute Account.linked?(account)
    assert_received {:sidecar, "POST", path, ["Bearer test-whatsmeow-token"]}
    assert path == "/sessions/#{account.session_id}/connect"

    {:ok, account} = Whatsapp.refresh(scope)
    assert Account.linked?(account)
    assert account.phone == "+34600111222"

    # Each owner gets a different session.
    {:ok, other} = Whatsapp.connect(user_scope_fixture())
    assert other.session_id != account.session_id
  end

  test "stores incoming messages in Caseo's format, once", %{scope: scope} do
    account = linked_account(scope)
    Whatsapp.subscribe(scope)

    event = event(account, %{"id" => "M1", "push_name" => "Ana", "text" => "¿Sigue disponible?"})

    assert {:error, :unauthorized} = Whatsapp.receive_event("whatsmeow", [], event)

    assert {:error, :unauthorized} =
             Whatsapp.receive_event("whatsmeow", [{"authorization", "Bearer nope"}], event)

    assert {:ok, %Message{} = message} = Whatsapp.receive_event("whatsmeow", @auth, event)
    assert message.contact_phone == "+34612345678"
    assert message.contact_name == "Ana"
    assert message.direction == :inbound
    assert message.type == :text
    assert message.body == "¿Sigue disponible?"
    assert_received {:whatsapp_message, %Message{id: id}}
    assert id == message.id

    assert {:ok, :duplicate} = Whatsapp.receive_event("whatsmeow", @auth, event)

    # Sent from the owner's phone: outbound, without the owner's name.
    assert {:ok, %Message{direction: :outbound, contact_name: nil}} =
             Whatsapp.receive_event(
               "whatsmeow",
               @auth,
               event(account, %{"id" => "M2", "from_me" => true, "push_name" => "Yo"})
             )

    assert {:ok, %Message{type: :image, body: nil}} =
             Whatsapp.receive_event(
               "whatsmeow",
               @auth,
               event(account, %{"id" => "M3", "type" => "image", "text" => ""})
             )

    assert {:error, :unknown_account} =
             Whatsapp.receive_event("whatsmeow", @auth, %{event | "session" => "unknown"})

    assert {:error, :unknown_account} = Whatsapp.receive_event("other", @auth, event)

    assert :ignore =
             Whatsapp.receive_event("whatsmeow", @auth, %{"session" => account.session_id})
  end

  test "sends only to people who wrote first or are leads, and records the 24-hour window",
       %{scope: scope} do
    account = linked_account(scope)
    test_pid = self()

    Req.Test.stub(Whatsmeow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:sent, conn.request_path, Jason.decode!(body)})

      Req.Test.json(conn, %{
        id: "OUT-#{System.unique_integer([:positive])}",
        timestamp: "2026-11-21T10:00:00Z"
      })
    end)

    assert {:error, :unknown_contact} = Whatsapp.send_text(scope, "+34612345678", "Hola")
    refute_received {:sent, _, _}

    {:ok, _} = Whatsapp.receive_event("whatsmeow", @auth, event(account, %{"id" => "IN1"}))
    assert {:ok, reply} = Whatsapp.send_text(scope, "612 345 678", "  Sí, sigue libre  ")
    assert reply.direction == :outbound
    assert reply.origin == :reply
    assert reply.body == "Sí, sigue libre"
    assert_received {:sent, path, %{"to" => "34612345678", "text" => "Sí, sigue libre"}}
    assert path == "/sessions/#{account.session_id}/send"

    # A lead who never wrote: Caseo starts the conversation.
    {:ok, _lead} = Leads.create_lead(scope, %{"name" => "Bea", "phone" => "622345678"})
    assert {:ok, %{origin: :initiated}} = Whatsapp.send_text(scope, "+34622345678", "Hola, Bea")

    assert {:error, :empty} = Whatsapp.send_text(scope, "+34612345678", "   ")
  end

  test "an owner cannot send from or read another owner's number", %{scope: scope} do
    account = linked_account(scope)
    {:ok, _} = Whatsapp.receive_event("whatsmeow", @auth, event(account, %{"id" => "IN1"}))

    other = user_scope_fixture()
    assert {:error, :not_linked} = Whatsapp.send_text(other, "+34612345678", "Hola")
    assert Whatsapp.get_account(other) == nil
  end

  test "rate limits and an unlinked sidecar surface as errors", %{scope: scope} do
    account = linked_account(scope)
    {:ok, _} = Whatsapp.receive_event("whatsmeow", @auth, event(account, %{"id" => "IN1"}))

    Req.Test.stub(Whatsmeow, &Plug.Conn.send_resp(&1, 429, ""))
    assert {:error, :rate_limited} = Whatsapp.send_text(scope, "+34612345678", "Hola")

    Req.Test.stub(Whatsmeow, &Plug.Conn.send_resp(&1, 204, ""))
    assert :ok = Whatsapp.disconnect(scope)
    refute Account.linked?(Whatsapp.get_account(scope))
    assert {:error, :not_linked} = Whatsapp.send_text(scope, "+34612345678", "Hola")
  end

  defp linked_account(scope) do
    %Account{
      owner_id: scope.user.id,
      provider: "whatsmeow",
      session_id: "s#{System.unique_integer([:positive])}",
      phone: "+34600111222",
      linked_at: DateTime.utc_now(:second)
    }
    |> Repo.insert!()
  end

  defp event(account, attrs) do
    Map.merge(
      %{
        "session" => account.session_id,
        "id" => "M#{System.unique_integer([:positive])}",
        "from" => "34612345678",
        "chat" => "34612345678",
        "push_name" => "Ana",
        "from_me" => false,
        "type" => "text",
        "text" => "Hola",
        "timestamp" => "2026-11-21T09:59:00Z"
      },
      attrs
    )
  end
end
