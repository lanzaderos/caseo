defmodule Caseo.Visits do
  @moduledoc """
  Schedules and tracks the owner's visits. A visit belongs to a lead's
  interest in a property or room, and every query is scoped through the lead's
  owner.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead
  alias Caseo.Repo
  alias Caseo.Visits.AvailabilityWindow
  alias Caseo.Visits.BookingLink
  alias Caseo.Visits.Visit

  @preloads [interest: [:lead, :property, :room]]

  @doc """
  Lists the owner's visits from `from` (default: today) onwards, soonest
  first. Pass `property_id` or `lead_id` to narrow them.
  """
  @spec list_visits(Scope.t(), keyword()) :: [Visit.t()]
  def list_visits(scope, opts \\ []) do
    from = Keyword.get(opts, :from, NaiveDateTime.beginning_of_day(NaiveDateTime.local_now()))

    scope
    |> owned_visits()
    |> where([v], v.starts_at >= ^from)
    |> filter_property(Keyword.get(opts, :property_id))
    |> filter_lead(Keyword.get(opts, :lead_id))
    |> order_by([v], asc: v.starts_at, asc: v.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc "Lists the upcoming scheduled or confirmed visits of an owned property."
  @spec list_pending_visits(Scope.t(), integer()) :: [Visit.t()]
  def list_pending_visits(scope, property_id) do
    scope
    |> list_visits(property_id: property_id, from: NaiveDateTime.local_now())
    |> Enum.filter(&(&1.status in Visit.pending_statuses()))
  end

  @doc "Fetches an owned visit."
  @spec fetch_visit(Scope.t(), term()) :: {:ok, Visit.t()} | {:error, :not_found}
  def fetch_visit(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Visit{} = visit <- scope |> owned_visits() |> preload(^@preloads) |> Repo.get(id) do
      {:ok, visit}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Builds a changeset for the visit form."
  @spec change_visit(Visit.t(), map()) :: Ecto.Changeset.t()
  def change_visit(visit, attrs \\ %{}), do: Visit.changeset(visit, attrs)

  @doc """
  Schedules a visit for an owned interest. A lead who was new or contacted
  moves to "visit scheduled".
  """
  @spec create_visit(Scope.t(), term(), map()) ::
          {:ok, Visit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def create_visit(scope, interest_id, attrs) do
    with {:ok, interest} <- Leads.fetch_interest(scope, interest_id) do
      Repo.transact(fn -> insert_visit(interest, attrs) end)
    end
  end

  defp insert_visit(interest, attrs) do
    with {:ok, visit} <-
           %Visit{interest_id: interest.id} |> Visit.changeset(attrs) |> Repo.insert() do
      if interest.status in [:new, :contacted],
        do: interest |> Ecto.Changeset.change(status: :visit_scheduled) |> Repo.update!()

      {:ok, visit}
    end
  end

  @doc "Updates, reschedules or cancels an owned visit."
  @spec update_visit(Scope.t(), term(), map()) ::
          {:ok, Visit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_visit(scope, id, attrs) do
    with {:ok, visit} <- fetch_visit(scope, id) do
      visit |> Visit.changeset(attrs) |> Repo.update()
    end
  end

  ## Availability

  @doc "Lists the owner's availability windows that have not ended yet."
  @spec list_windows(Scope.t()) :: [AvailabilityWindow.t()]
  def list_windows(%Scope{user: %{id: owner_id}}),
    do: active_windows(owner_id, NaiveDateTime.local_now())

  # One-off windows that have not ended, and weekly ones still repeating.
  defp active_windows(owner_id, now) do
    today = NaiveDateTime.to_date(now)

    Repo.all(
      from w in AvailabilityWindow,
        where:
          w.owner_id == ^owner_id and
            (w.ends_at > ^now or
               (w.weekly and (is_nil(w.repeat_until) or w.repeat_until >= ^today))),
        order_by: [asc: w.starts_at]
    )
  end

  @doc "Builds a changeset for the availability form."
  @spec change_window(AvailabilityWindow.t(), map()) :: Ecto.Changeset.t()
  def change_window(window, attrs \\ %{}), do: AvailabilityWindow.changeset(window, attrs)

  @doc "Adds an availability window for the owner."
  @spec create_window(Scope.t(), map()) ::
          {:ok, AvailabilityWindow.t()} | {:error, Ecto.Changeset.t()}
  def create_window(%Scope{user: %{id: owner_id}}, attrs) do
    %AvailabilityWindow{owner_id: owner_id}
    |> AvailabilityWindow.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Removes an owned availability window. Booked visits stay."
  @spec delete_window(Scope.t(), term()) :: :ok | {:error, :not_found}
  def delete_window(%Scope{user: %{id: owner_id}}, id) do
    with {:ok, id} <- cast_id(id) do
      query = from w in AvailabilityWindow, where: w.id == ^id and w.owner_id == ^owner_id

      case Repo.delete_all(query) do
        {1, _} -> :ok
        {0, _} -> {:error, :not_found}
      end
    end
  end

  @doc """
  Lists the owner's free slots from now on as `{starts_at, minutes}`. A slot
  is free when no pending visit of the owner overlaps it.
  """
  @spec free_slots(Scope.t() | integer()) :: [{NaiveDateTime.t(), pos_integer()}]
  def free_slots(%Scope{user: %{id: owner_id}}), do: free_slots(owner_id)

  # ponytail: compares every slot with every pending visit; index by day if
  # owners publish hundreds of slots.
  def free_slots(owner_id) when is_integer(owner_id) do
    now = NaiveDateTime.local_now()

    windows =
      owner_id
      |> active_windows(now)
      |> Enum.flat_map(&AvailabilityWindow.occurrences(&1, now))

    busy =
      owner_id
      |> owner_visits()
      |> where(
        [v],
        v.status in ^Visit.pending_statuses() and v.starts_at >= ^NaiveDateTime.add(now, -1, :day)
      )
      |> Repo.all()
      |> Enum.map(&{&1.starts_at, Visit.ends_at(&1)})

    for window <- windows,
        starts_at <- AvailabilityWindow.slots(window),
        NaiveDateTime.compare(starts_at, now) == :gt,
        ends_at = NaiveDateTime.add(starts_at, window.slot_minutes, :minute),
        not Enum.any?(busy, fn {from, to} -> overlaps?(starts_at, ends_at, from, to) end),
        uniq: true do
      {starts_at, window.slot_minutes}
    end
    |> Enum.sort_by(&elem(&1, 0), NaiveDateTime)
  end

  defp overlaps?(start_a, end_a, start_b, end_b),
    do: NaiveDateTime.before?(start_a, end_b) and NaiveDateTime.before?(start_b, end_a)

  ## Booking links

  @doc """
  Creates a booking link for an owned interest and returns its clear token.
  Earlier open links of the interest are revoked.
  """
  @spec create_booking_link(Scope.t(), term()) :: {:ok, String.t()} | {:error, :not_found}
  def create_booking_link(scope, interest_id) do
    with {:ok, interest} <- Leads.fetch_interest(scope, interest_id) do
      {link, token} = BookingLink.build(interest.id)

      Repo.transact(fn ->
        revoke_open_links(interest.id)
        {:ok, Repo.insert!(link)}
      end)

      {:ok, token}
    end
  end

  @doc "Revokes the open booking links of an owned interest."
  @spec revoke_booking_links(Scope.t(), term()) :: :ok | {:error, :not_found}
  def revoke_booking_links(scope, interest_id) do
    with {:ok, interest} <- Leads.fetch_interest(scope, interest_id) do
      revoke_open_links(interest.id)
      :ok
    end
  end

  defp revoke_open_links(interest_id) do
    now = DateTime.utc_now(:second)

    Repo.update_all(
      from(l in BookingLink,
        where: l.interest_id == ^interest_id and is_nil(l.revoked_at) and is_nil(l.visit_id)
      ),
      set: [revoked_at: now, updated_at: now]
    )
  end

  @doc """
  Fetches a booking link by its clear token, with the interest (lead,
  property, room) and the booked visit. Closed links are returned too so the
  page can say why.
  """
  @spec fetch_booking_link(String.t()) :: {:ok, BookingLink.t()} | {:error, :not_found}
  def fetch_booking_link(token) when is_binary(token) do
    case Repo.get_by(BookingLink, token_hash: BookingLink.hash(token)) do
      %BookingLink{} = link ->
        {:ok, Repo.preload(link, [:visit, interest: [:lead, :property, :room]])}

      nil ->
        {:error, :not_found}
    end
  end

  def fetch_booking_link(_token), do: {:error, :not_found}

  @doc """
  Requests the slot starting at `starts_at` through a booking link. The visit
  is created pending the owner's approval and the link closes.
  """
  @spec book(String.t(), term()) ::
          {:ok, Visit.t()} | {:error, :not_found | :closed | :slot_taken}
  def book(token, starts_at) do
    with {:ok, link} <- fetch_booking_link(token),
         {:ok, starts_at} <- Ecto.Type.cast(:naive_datetime, starts_at) do
      owner_id = link.interest.lead.owner_id

      Repo.transact(fn -> book_slot(link, owner_id, starts_at) end)
    else
      {:error, :not_found} -> {:error, :not_found}
      :error -> {:error, :slot_taken}
    end
  end

  defp book_slot(link, owner_id, starts_at) do
    # Serialize bookings of the same owner so two leads cannot take one slot.
    Repo.one!(
      from u in Caseo.Accounts.User, where: u.id == ^owner_id, lock: "FOR UPDATE", select: u.id
    )

    link = link |> Repo.reload!() |> Repo.preload(:interest)

    with true <- BookingLink.open?(link) || {:error, :closed},
         {:ok, minutes} <- free_slot_minutes(owner_id, starts_at),
         {:ok, visit} <-
           insert_visit(link.interest, %{
             "starts_at" => starts_at,
             "duration_minutes" => minutes,
             "status" => "requested"
           }) do
      link |> Ecto.Changeset.change(visit_id: visit.id) |> Repo.update!()
      {:ok, visit}
    end
  end

  defp free_slot_minutes(owner_id, starts_at) do
    case List.keyfind(free_slots(owner_id), starts_at, 0) do
      {_starts_at, minutes} -> {:ok, minutes}
      nil -> {:error, :slot_taken}
    end
  end

  defp owner_visits(owner_id) do
    from v in Visit,
      join: i in Interest,
      on: i.id == v.interest_id,
      join: l in Lead,
      on: l.id == i.lead_id,
      where: l.owner_id == ^owner_id
  end

  defp filter_property(query, nil), do: query

  defp filter_property(query, property_id),
    do: where(query, [interest: i], i.property_id == ^property_id)

  defp filter_lead(query, nil), do: query
  defp filter_lead(query, lead_id), do: where(query, [interest: i], i.lead_id == ^lead_id)

  defp owned_visits(%Scope{user: %{id: owner_id}}) when is_integer(owner_id) do
    from v in Visit,
      join: i in Interest,
      as: :interest,
      on: i.id == v.interest_id,
      join: l in Lead,
      on: l.id == i.lead_id,
      where: l.owner_id == ^owner_id
  end

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
