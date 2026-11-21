defmodule Caseo.Visits.Visit do
  @moduledoc """
  A lead's visit to a property or room. It hangs off the lead's interest, so
  the property, room and lead always match the link.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:scheduled, :confirmed, :done, :no_show, :cancelled]

  schema "visits" do
    belongs_to :interest, Caseo.Leads.Interest
    # ponytail: wall-clock time in the owner's timezone (Spain); store UTC with
    # tzdata once owners span several timezones.
    field :starts_at, :naive_datetime
    field :duration_minutes, :integer, default: 30
    field :status, Ecto.Enum, values: @statuses, default: :scheduled
    field :notes, :string
    # Earlier times, newest last: %{"from" => ISO 8601, "at" => ISO 8601}.
    field :reschedules, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc "Statuses with their labels."
  def status_options do
    [
      {"Programada", :scheduled},
      {"Confirmada", :confirmed},
      {"Realizada", :done},
      {"No se presentó", :no_show},
      {"Cancelada", :cancelled}
    ]
  end

  @doc "Returns the label of a status."
  def status_label(status) do
    Enum.find_value(status_options(), fn {label, value} -> value == status && label end)
  end

  @doc "Statuses of visits still to happen."
  def pending_statuses, do: [:scheduled, :confirmed]

  @doc """
  Validates a visit. Moving `starts_at` of a saved visit records the previous
  time in `reschedules`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:starts_at, :duration_minutes, :status, :notes])
    |> validate_required([:starts_at, :duration_minutes, :status])
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_length(:notes, max: 5_000)
    |> track_reschedule()
  end

  defp track_reschedule(%{data: %{id: id, starts_at: from}} = changeset) when not is_nil(id) do
    if changed?(changeset, :starts_at) do
      entry = %{
        "from" => NaiveDateTime.to_iso8601(from),
        "at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
      }

      put_change(changeset, :reschedules, changeset.data.reschedules ++ [entry])
    else
      changeset
    end
  end

  defp track_reschedule(changeset), do: changeset

  @doc "Ends of the visit."
  def ends_at(%__MODULE__{starts_at: starts_at, duration_minutes: minutes}),
    do: NaiveDateTime.add(starts_at, minutes, :minute)
end
