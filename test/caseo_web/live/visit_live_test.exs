defmodule CaseoWeb.VisitLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Leads
  alias Caseo.Properties
  alias Caseo.Visits

  test "schedules a visit from a lead, reschedules it, marks it done and cancels another",
       %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)

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

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, property.id)

    {:ok, lead_view, _html} = live(conn, ~p"/interesados/#{lead.id}")

    lead_view |> element("#schedule-visit-#{interest.id}") |> render_click()

    {:ok, form_view, _html} =
      lead_view
      |> element("#schedule-manually")
      |> render_click()
      |> follow_redirect(conn)

    {:ok, visit_view, _html} =
      form_view
      |> form("#visit-form", visit: %{starts_at: local(2, "10:30"), duration_minutes: "45"})
      |> render_submit()
      |> follow_redirect(conn)

    [visit] = Visits.list_visits(scope)
    assert visit.duration_minutes == 45

    {:ok, agenda, _html} = live(conn, ~p"/visitas?#{[inmueble: property.id]}")
    assert has_element?(agenda, "#visit-#{visit.id}")

    {:ok, detail, _html} = live(conn, ~p"/inmuebles/#{property.id}")
    assert has_element?(detail, "#property-visit-#{visit.id}")

    # Reschedule: the previous time stays in the history.
    {:ok, visit_view, _html} =
      visit_view
      |> form("#visit-form", visit: %{starts_at: local(3, "17:00")})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(visit_view, "#visit-history")

    # Done: Caseo suggests moving the lead to "visited".
    visit_view |> form("#visit-form", visit: %{status: "done"}) |> render_submit()
    {:ok, visit_view, _html} = live(conn, ~p"/visitas/#{visit.id}")
    visit_view |> element("#mark-visited") |> render_click()
    assert {:ok, %{status: :visited}} = Leads.fetch_interest(scope, interest.id)
    refute has_element?(visit_view, "#suggest-visited")

    # Cancel a second visit from its page.
    {:ok, other} = Visits.create_visit(scope, interest.id, %{"starts_at" => local(4, "12:00")})
    {:ok, other_view, _html} = live(conn, ~p"/visitas/#{other.id}")
    other_view |> element("#cancel-visit") |> render_click()
    assert {:ok, %{status: :cancelled}} = Visits.fetch_visit(scope, other.id)
  end

  test "another owner cannot open a visit", %{conn: conn} do
    scope = user_scope_fixture()

    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso",
        "mode" => "rental",
        "rent" => "900",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid"
      })

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, property.id)
    {:ok, visit} = Visits.create_visit(scope, interest.id, %{"starts_at" => local(1, "09:00")})

    conn = log_in_user(conn, user_fixture())
    assert {:error, {:live_redirect, %{to: "/visitas"}}} = live(conn, ~p"/visitas/#{visit.id}")

    assert {:error, {:live_redirect, %{to: "/visitas"}}} =
             live(conn, ~p"/visitas/nueva?#{[interes: interest.id]}")

    {:ok, agenda, _html} = live(conn, ~p"/visitas")
    assert has_element?(agenda, "#visits-empty")
  end

  defp local(days, time), do: "#{Date.add(Date.utc_today(), days)}T#{time}"
end
