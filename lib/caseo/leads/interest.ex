defmodule Caseo.Leads.Interest do
  @moduledoc "Links a lead to a property, or to one of its rooms, with a pipeline status."

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Property
  alias Caseo.Properties.Requirements

  @type t :: %__MODULE__{}

  @check_values ~w(met unmet pending)

  @statuses [:new, :contacted, :visit_scheduled, :visited, :offer, :closed, :discarded]

  schema "lead_interests" do
    belongs_to :lead, Caseo.Leads.Lead
    belongs_to :property, Caseo.Properties.Property
    belongs_to :room, Caseo.Properties.Room
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :discard_reason, :string
    # Requirement key => "met" | "unmet" | "pending". Only the outcome is kept,
    # never the documents behind it (#12).
    field :checks, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "Statuses in pipeline order, with their labels."
  def status_options do
    [
      {"Nuevo", :new},
      {"Contactado", :contacted},
      {"Visita programada", :visit_scheduled},
      {"Visitado", :visited},
      {"Reserva u oferta", :offer},
      {"Cerrado", :closed},
      {"Descartado", :discarded}
    ]
  end

  @doc "Checklist outcomes, with their labels."
  def check_options, do: [{"Pendiente", "pending"}, {"Cumple", "met"}, {"No cumple", "unmet"}]

  @doc """
  Returns the requirement checklist of the interest as `{key, label, outcome}`.
  Needs `:property` (with rooms) and `:room` preloaded.
  """
  @spec checklist(t()) :: [{String.t(), String.t(), String.t()}]
  def checklist(%__MODULE__{} = interest) do
    {requirements, _commission, price} = Property.terms(interest.property, interest.room)

    for {key, label} <- Requirements.checklist(requirements, price) do
      {key, label, Map.get(interest.checks, key, "pending")}
    end
  end

  @doc "Summarizes the checklist, e.g. \"3/4 requisitos\", or `nil` without requirements."
  @spec checklist_label(t()) :: String.t() | nil
  def checklist_label(interest) do
    case checklist(interest) do
      [] -> nil
      items -> "#{Enum.count(items, &(elem(&1, 2) == "met"))}/#{length(items)} requisitos"
    end
  end

  @doc "Returns the label of a status."
  def status_label(status) do
    Enum.find_value(status_options(), fn {label, value} -> value == status && label end)
  end

  @doc "Validates a status change. Discarding requires a reason."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(interest, attrs) do
    changeset =
      interest
      |> cast(attrs, [:status, :discard_reason, :checks])
      |> validate_required([:status])
      |> validate_length(:discard_reason, max: 255)
      |> validate_change(:checks, fn :checks, checks ->
        if Enum.all?(checks, &valid_check?/1), do: [], else: [checks: "no es válido"]
      end)

    if get_field(changeset, :status) == :discarded do
      validate_required(changeset, [:discard_reason], message: "indica el motivo del descarte")
    else
      put_change(changeset, :discard_reason, nil)
    end
  end

  defp valid_check?({key, value}), do: key in Requirements.keys() and value in @check_values
end
