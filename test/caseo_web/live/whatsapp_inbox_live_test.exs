defmodule CaseoWeb.WhatsappInboxLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Leads
  alias Caseo.Properties
  alias Caseo.Repo
  alias Caseo.Visits
  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Whatsmeow

  @auth [{"authorization", "Bearer test-whatsmeow-token"}]

  setup %{conn: conn} do
    scope = user_scope_fixture()

    account =
      Repo.insert!(%Account{
        owner_id: scope.user.id,
        provider: "whatsmeow",
        session_id: "s#{System.unique_integer([:positive])}",
        phone: "+34600111222",
        linked_at: DateTime.utc_now(:second)
      })

    test_pid = self()

    Req.Test.stub(Whatsmeow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:sent, Jason.decode!(body)})

      Req.Test.json(conn, %{
        id: "OUT-#{System.unique_integer([:positive])}",
        timestamp: DateTime.to_iso8601(DateTime.utc_now())
      })
    end)

    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso centro",
        "mode" => "rental",
        "rent" => "900",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid"
      })

    %{conn: log_in_user(conn, scope.user), scope: scope, account: account, property: property}
  end

  test "new messages appear without reloading, and the owner replies", ctx do
    {:ok, inbox, _html} = live(ctx.conn, ~p"/whatsapp")
    assert has_element?(inbox, "#conversations-empty")

    receive_message(ctx.account, "Hola, ¿sigue disponible el piso?")
    assert has_element?(inbox, "#conversation-34612345678")
    assert has_element?(inbox, "#unread-34612345678")

    {:ok, chat, _html} = live(ctx.conn, ~p"/whatsapp/34612345678")
    assert has_element?(chat, "#chat-title", "Ana")
    refute has_element?(chat, "#unread-34612345678")

    receive_message(ctx.account, "¿Puedo verlo mañana?")
    assert render(element(chat, "#messages")) =~ "¿Puedo verlo mañana?"

    chat |> form("#message-form", message: %{body: "Sí, claro"}) |> render_submit()
    assert_received {:sent, %{"to" => "34612345678", "text" => "Sí, claro"}}
    assert render(element(chat, "#messages")) =~ "Sí, claro"
  end

  test "from a new chat: create the lead, link the property and schedule a visit", ctx do
    receive_message(ctx.account, "Hola, me interesa")
    {:ok, chat, _html} = live(ctx.conn, ~p"/whatsapp/34612345678")

    assert has_element?(chat, "#panel-new-lead")
    chat |> form("#create-lead-form", lead: %{name: "Ana López"}) |> render_submit()

    lead = Leads.get_lead_by_phone(ctx.scope, "+34612345678")
    assert lead.name == "Ana López"
    assert lead.source == :whatsapp

    chat
    |> form("#panel-link-form", link: %{target: to_string(ctx.property.id)})
    |> render_submit()

    [interest] = Leads.list_property_interests(ctx.scope, ctx.property.id)
    assert has_element?(chat, "#panel-interest-#{interest.id}")

    # The popup sends the booking link from the linked number.
    {:ok, _window} =
      Visits.create_window(ctx.scope, %{
        "date" => Date.add(Date.utc_today(), 1),
        "from" => "10:00",
        "to" => "11:00",
        "slot_minutes" => "30"
      })

    chat |> element("#panel-schedule-#{interest.id}") |> render_click()
    chat |> element("#create-booking-link") |> render_click()
    chat |> element("#send-booking-whatsapp") |> render_click()
    assert_received {:sent, %{"to" => "34612345678", "text" => "Hola Ana, elige cuándo" <> _}}

    # Or the owner picks the date: the visit lands in the agenda.
    {:ok, form, _html} =
      chat
      |> element("#schedule-manually")
      |> render_click()
      |> follow_redirect(ctx.conn)

    form
    |> form("#visit-form", visit: %{starts_at: "#{Date.add(Date.utc_today(), 2)}T10:30"})
    |> render_submit()

    assert [%{interest_id: interest_id}] = Visits.list_visits(ctx.scope)
    assert interest_id == interest.id
  end

  test "an Idealista link in the chat suggests the imported property", ctx do
    ctx.property
    |> Ecto.Changeset.change(listing_source: "idealista", listing_external_id: "98765432")
    |> Repo.update!()

    {:ok, _lead} = Leads.create_lead(ctx.scope, %{"name" => "Ana", "phone" => "612345678"})
    receive_message(ctx.account, "Me interesa este: https://www.idealista.com/inmueble/98765432/")

    {:ok, chat, _html} = live(ctx.conn, ~p"/whatsapp/34612345678")
    assert has_element?(chat, "#listing-suggestion", "Piso centro")

    chat |> element("#link-suggested") |> render_click()
    assert [_interest] = Leads.list_property_interests(ctx.scope, ctx.property.id)
    refute has_element?(chat, "#listing-suggestion")
  end

  test "an owner does not see another owner's conversations", ctx do
    receive_message(ctx.account, "Hola")

    other_conn = log_in_user(build_conn(), user_fixture())
    {:ok, inbox, _html} = live(other_conn, ~p"/whatsapp")
    assert has_element?(inbox, "#conversations-empty")
    refute has_element?(inbox, "#conversation-34612345678")

    {:ok, chat, _html} = live(other_conn, ~p"/whatsapp/34612345678")
    assert has_element?(chat, "#messages-empty")
    refute render(element(chat, "#messages")) =~ "Hola"
  end

  defp receive_message(account, text) do
    {:ok, _message} =
      Whatsapp.receive_event("whatsmeow", @auth, %{
        "session" => account.session_id,
        "id" => "IN-#{System.unique_integer([:positive])}",
        "chat" => "34612345678",
        "push_name" => "Ana",
        "from_me" => false,
        "type" => "text",
        "text" => text,
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      })
  end
end
