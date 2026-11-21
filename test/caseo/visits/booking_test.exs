defmodule Caseo.Visits.BookingTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Leads
  alias Caseo.Properties
  alias Caseo.Repo
  alias Caseo.Visits
  alias Caseo.Visits.BookingLink

  setup do
    scope = user_scope_fixture()

    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso compartido",
        "mode" => "rooms",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid",
        "rooms" => [%{"name" => "Habitación sur", "rent" => "450"}]
      })

    [room] = property.rooms
    {:ok, ana} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, bea} = Leads.create_lead(scope, %{"name" => "Bea", "phone" => "622345678"})
    {:ok, ana_interest} = Leads.add_interest(scope, ana.id, property.id, room.id)
    {:ok, bea_interest} = Leads.add_interest(scope, bea.id, property.id)

    # Tomorrow 10:00–11:00 in 30-minute slots.
    {:ok, _window} =
      Visits.create_window(scope, %{
        "date" => Date.add(Date.utc_today(), 1),
        "from" => "10:00",
        "to" => "11:00",
        "slot_minutes" => "30"
      })

    %{scope: scope, property: property, room: room, ana: ana_interest, bea: bea_interest}
  end

  test "splits windows into slots and hides those taken by pending visits", ctx do
    assert [{ten, 30}, {half_past, 30}] = Visits.free_slots(ctx.scope)
    assert ten.hour == 10 and ten.minute == 0
    assert half_past.minute == 30

    {:ok, _manual} =
      Visits.create_visit(ctx.scope, ctx.bea.id, %{"starts_at" => ten, "duration_minutes" => 20})

    assert [{^half_past, 30}] = Visits.free_slots(ctx.scope)
    assert Visits.free_slots(user_scope_fixture()) == []
  end

  test "weekly windows repeat every week up to the horizon or their end date" do
    scope = user_scope_fixture()
    today = Date.utc_today()

    # Started six days ago: the next occurrence is tomorrow, then every 7 days.
    {:ok, _weekly} =
      Visits.create_window(scope, %{
        "date" => Date.add(today, -6),
        "from" => "09:00",
        "to" => "09:30",
        "slot_minutes" => "30",
        "weekly" => "true"
      })

    dates = scope |> Visits.free_slots() |> Enum.map(&NaiveDateTime.to_date(elem(&1, 0)))
    assert dates == Enum.map(0..3, &Date.add(today, 1 + 7 * &1))

    # With an end date, it stops there.
    other = user_scope_fixture()

    {:ok, _weekly} =
      Visits.create_window(other, %{
        "date" => Date.add(today, 1),
        "from" => "09:00",
        "to" => "10:00",
        "slot_minutes" => "60",
        "weekly" => "true",
        "repeat_until" => Date.add(today, 8)
      })

    assert [{first, 60}, {second, 60}] = Visits.free_slots(other)
    assert NaiveDateTime.to_date(first) == Date.add(today, 1)
    assert NaiveDateTime.to_date(second) == Date.add(today, 8)

    assert {:error, changeset} =
             Visits.create_window(other, %{
               "date" => today,
               "from" => "09:00",
               "to" => "10:00",
               "weekly" => "true",
               "repeat_until" => Date.add(today, -1)
             })

    assert %{repeat_until: [_]} = errors_on(changeset)
  end

  test "a lead requests a slot through their link; the slot closes for everyone", ctx do
    {:ok, ana_token} = Visits.create_booking_link(ctx.scope, ctx.ana.id)
    {:ok, bea_token} = Visits.create_booking_link(ctx.scope, ctx.bea.id)
    [{ten, _}, _] = Visits.free_slots(ctx.scope)

    assert {:ok, visit} = Visits.book(ana_token, NaiveDateTime.to_iso8601(ten))
    assert visit.status == :requested
    assert visit.interest_id == ctx.ana.id
    assert visit.duration_minutes == 30

    {:ok, visit} = Visits.fetch_visit(ctx.scope, visit.id)
    assert visit.interest.room.id == ctx.room.id
    assert {:ok, %{status: :visit_scheduled}} = Leads.fetch_interest(ctx.scope, ctx.ana.id)

    # The slot is gone for the other lead, and Ana's link is used up.
    assert {:error, :slot_taken} = Visits.book(bea_token, NaiveDateTime.to_iso8601(ten))
    [{half_past, _}] = Visits.free_slots(ctx.scope)
    assert {:error, :closed} = Visits.book(ana_token, NaiveDateTime.to_iso8601(half_past))

    # A slot that is not offered cannot be booked.
    assert {:error, :slot_taken} = Visits.book(bea_token, "2030-01-01T03:00:00")
    assert {:error, :slot_taken} = Visits.book(bea_token, "not a date")

    # Approving confirms the visit.
    assert {:ok, %{status: :confirmed}} =
             Visits.update_visit(ctx.scope, visit.id, %{"status" => "confirmed"})
  end

  test "revoked, replaced, expired and unknown links are closed", ctx do
    [{ten, _} | _] = Visits.free_slots(ctx.scope)
    slot = NaiveDateTime.to_iso8601(ten)

    {:ok, first} = Visits.create_booking_link(ctx.scope, ctx.ana.id)
    {:ok, second} = Visits.create_booking_link(ctx.scope, ctx.ana.id)
    assert {:error, :closed} = Visits.book(first, slot)

    :ok = Visits.revoke_booking_links(ctx.scope, ctx.ana.id)
    assert {:error, :closed} = Visits.book(second, slot)

    {:ok, third} = Visits.create_booking_link(ctx.scope, ctx.ana.id)
    {:ok, link} = Visits.fetch_booking_link(third)
    link |> Ecto.Changeset.change(expires_at: ~U[2020-01-01 00:00:00Z]) |> Repo.update!()
    refute BookingLink.open?(Repo.reload!(link))
    assert {:error, :closed} = Visits.book(third, slot)

    assert {:error, :not_found} = Visits.book("unknown", slot)
    assert {:error, :not_found} = Visits.fetch_booking_link("unknown")
  end

  test "other owners cannot create links, revoke them or remove windows", ctx do
    other = user_scope_fixture()
    [window] = Visits.list_windows(ctx.scope)

    assert {:error, :not_found} = Visits.create_booking_link(other, ctx.ana.id)
    assert {:error, :not_found} = Visits.revoke_booking_links(other, ctx.ana.id)
    assert {:error, :not_found} = Visits.delete_window(other, window.id)
    assert Visits.list_windows(other) == []
    assert :ok = Visits.delete_window(ctx.scope, window.id)
  end
end
