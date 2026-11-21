defmodule CaseoWeb.BookingLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Leads
  alias Caseo.Properties
  alias Caseo.Visits

  test "the owner sends a booking link, the lead books a slot and the owner approves it",
       %{conn: conn} do
    scope = user_scope_fixture()
    owner_conn = log_in_user(conn, scope.user)

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

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana López", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, property.id)
    tomorrow = Date.add(Date.utc_today(), 1)

    # Availability from the calendar page.
    {:ok, availability, _html} = live(owner_conn, ~p"/visitas/disponibilidad")

    availability
    |> form("#availability-form",
      availability_window: %{date: tomorrow, from: "17:00", to: "18:00", slot_minutes: "30"}
    )
    |> render_submit()

    assert [_, _] = Visits.free_slots(scope)

    availability
    |> form("#availability-form",
      availability_window: %{date: tomorrow, from: "09:00", to: "09:30", weekly: "true"}
    )
    |> render_change()

    availability
    |> form("#availability-form",
      availability_window: %{
        date: tomorrow,
        from: "09:00",
        to: "09:30",
        slot_minutes: "30",
        weekly: "true",
        repeat_until: Date.add(tomorrow, 7)
      }
    )
    |> render_submit()

    assert has_element?(availability, "#weekly-windows")
    assert length(Visits.free_slots(scope)) == 4

    # Popup on the lead page: generate the link and send it through WhatsApp.
    {:ok, lead_view, _html} = live(owner_conn, ~p"/interesados/#{lead.id}")
    lead_view |> element("#schedule-visit-#{interest.id}") |> render_click()
    assert has_element?(lead_view, "#schedule-modal")
    lead_view |> element("#create-booking-link") |> render_click()

    assert has_element?(
             lead_view,
             "#send-booking-whatsapp[href^='https://wa.me/34612345678?text=']"
           )

    url =
      lead_view
      |> element("#booking-url")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("value")
      |> List.first()

    path = URI.parse(url).path

    # The lead books without an account.
    {:ok, booking, _html} = live(build_conn(), path)
    assert has_element?(booking, "#booking-privacy")
    booking |> element("#slot-#{Calendar.strftime(tomorrow, "%Y%m%d")}1700") |> render_click()
    assert has_element?(booking, "#booking-requested")

    [visit] = Visits.list_visits(scope)
    assert visit.status == :requested

    # The owner approves it from the agenda.
    {:ok, agenda, _html} = live(owner_conn, ~p"/visitas")
    agenda |> element("#approve-visit-#{visit.id}") |> render_click()
    assert {:ok, %{status: :confirmed}} = Visits.fetch_visit(scope, visit.id)

    # A revoked link no longer offers slots.
    {:ok, token} = Visits.create_booking_link(scope, interest.id)
    :ok = Visits.revoke_booking_links(scope, interest.id)
    {:ok, closed, _html} = live(build_conn(), ~p"/reservar/#{token}")
    assert has_element?(closed, "#booking-closed")

    {:ok, unknown, _html} = live(build_conn(), ~p"/reservar/unknown")
    assert has_element?(unknown, "#booking-unavailable")
  end
end
