defmodule Caseo.Visits.AvailabilityWindow do
  @moduledoc """
  A stretch of time in which the owner holds visits, split into slots. A
  weekly window repeats on the same weekday and hours, forever or until
  `repeat_until`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  # ponytail: weekly windows are expanded this far ahead; raise it, or let
  # owners pick it, if leads need to book further out.
  @horizon_days 28

  schema "availability_windows" do
    belongs_to :owner, Caseo.Accounts.User
    field :date, :date, virtual: true
    field :from, :time, virtual: true
    field :to, :time, virtual: true
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :slot_minutes, :integer, default: 30
    field :weekly, :boolean, default: false
    field :repeat_until, :date

    timestamps(type: :utc_datetime)
  end

  @doc "Validates a window entered as a date and a time range."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(window, attrs) do
    changeset =
      window
      |> cast(attrs, [:date, :from, :to, :slot_minutes, :weekly, :repeat_until])
      |> validate_required([:date, :from, :to, :slot_minutes])
      |> validate_number(:slot_minutes, greater_than_or_equal_to: 10, less_than_or_equal_to: 240)
      |> change_repeat()

    with %{valid?: true} <- changeset,
         date = get_field(changeset, :date),
         from = get_field(changeset, :from),
         to = get_field(changeset, :to),
         :lt <- Time.compare(from, to) do
      changeset
      |> put_change(:starts_at, NaiveDateTime.new!(date, from))
      |> put_change(:ends_at, NaiveDateTime.new!(date, to))
    else
      %Ecto.Changeset{} = invalid -> invalid
      _ -> add_error(changeset, :to, "debe ser posterior a la hora de inicio")
    end
  end

  defp change_repeat(changeset) do
    date = get_field(changeset, :date)
    until = get_field(changeset, :repeat_until)

    cond do
      !get_field(changeset, :weekly) ->
        put_change(changeset, :repeat_until, nil)

      date && until && Date.before?(until, date) ->
        add_error(changeset, :repeat_until, "debe ser posterior al primer día")

      true ->
        changeset
    end
  end

  @doc """
  Expands the window into its occurrences that end after `now`. A weekly
  window yields one occurrence per week up to the booking horizon.
  """
  @spec occurrences(t(), NaiveDateTime.t()) :: [t()]
  def occurrences(%__MODULE__{weekly: false} = window, now) do
    if NaiveDateTime.after?(window.ends_at, now), do: [window], else: []
  end

  def occurrences(%__MODULE__{} = window, now) do
    horizon = now |> NaiveDateTime.to_date() |> Date.add(@horizon_days)

    last =
      if window.repeat_until, do: Enum.min([window.repeat_until, horizon], Date), else: horizon

    0
    |> Stream.iterate(&(&1 + 7))
    |> Stream.map(fn days ->
      %{
        window
        | starts_at: NaiveDateTime.add(window.starts_at, days, :day),
          ends_at: NaiveDateTime.add(window.ends_at, days, :day)
      }
    end)
    |> Enum.take_while(&(Date.compare(NaiveDateTime.to_date(&1.starts_at), last) != :gt))
    |> Enum.filter(&NaiveDateTime.after?(&1.ends_at, now))
  end

  @doc "Start times of the slots in the window."
  @spec slots(t()) :: [NaiveDateTime.t()]
  def slots(%__MODULE__{starts_at: starts_at, ends_at: ends_at, slot_minutes: minutes}) do
    starts_at
    |> Stream.iterate(&NaiveDateTime.add(&1, minutes, :minute))
    |> Enum.take_while(
      &(NaiveDateTime.compare(NaiveDateTime.add(&1, minutes, :minute), ends_at) != :gt)
    )
  end
end
