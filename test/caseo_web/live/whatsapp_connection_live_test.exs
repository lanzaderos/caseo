defmodule CaseoWeb.WhatsappConnectionLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Repo
  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Whatsmeow

  @png <<137, 80, 78, 71, 13, 10, 26, 10>>

  test "links the number with a QR code and unlinks it", %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)
    {:ok, linked} = Agent.start_link(fn -> false end)

    Req.Test.stub(Whatsmeow, fn conn ->
      case conn.request_path |> String.split("/") |> List.last() do
        "qr.png" ->
          conn |> Plug.Conn.put_resp_content_type("image/png") |> Plug.Conn.send_resp(200, @png)

        "logout" ->
          Agent.update(linked, fn _ -> false end)
          Plug.Conn.send_resp(conn, 204, "")

        _connect_or_status ->
          logged_in = Agent.get(linked, & &1)

          Req.Test.json(conn, %{
            connected: true,
            logged_in: logged_in,
            jid: if(logged_in, do: "34600111222", else: "")
          })
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/whatsapp/vincular")
    assert has_element?(view, "#whatsapp-unlinked")
    assert has_element?(view, "#whatsapp-warning")

    view |> element("#link-whatsapp") |> render_click()
    assert has_element?(view, "#whatsapp-qr")

    # The QR image is served only to its owner.
    response = get(conn, ~p"/whatsapp/qr.png")
    assert response(response, 200) == @png
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert response(get(log_in_user(build_conn(), user_fixture()), ~p"/whatsapp/qr.png"), 204)

    # The phone scans the code; the next poll sees the number linked.
    Agent.update(linked, fn _ -> true end)
    send(view.pid, :poll)
    assert has_element?(view, "#whatsapp-linked")
    assert Account.linked?(Whatsapp.get_account(scope))

    view |> element("#unlink-whatsapp") |> render_click()
    assert has_element?(view, "#whatsapp-unlinked")
  end

  test "shows when the sidecar does not answer", %{conn: conn} do
    scope = user_scope_fixture()

    Repo.insert!(%Account{owner_id: scope.user.id, provider: "whatsmeow", session_id: "s1"})
    Req.Test.stub(Whatsmeow, &Req.Test.transport_error(&1, :econnrefused))

    {:ok, view, _html} = live(log_in_user(conn, scope.user), ~p"/whatsapp/vincular")
    assert has_element?(view, "#whatsapp-unavailable")
  end
end
