defmodule Caseo.Leads.Interest do
  @moduledoc "Links a lead to a property, or to one of its rooms, with a pipeline status."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:new, :contacted, :visit_scheduled, :visited, :offer, :closed, :discarded]

  schema "lead_interests" do
    belongs_to :lead, Caseo.Leads.Lead
    belongs_to :property, Caseo.Properties.Property
    belongs_to :room, Caseo.Properties.Room
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :discard_reason, :string

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

  @doc "Returns the label of a status."
  def status_label(status) do
    Enum.find_value(status_options(), fn {label, value} -> value == status && label end)
  end

  @doc "Validates a status change. Discarding requires a reason."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(interest, attrs) do
    changeset =
      interest
      |> cast(attrs, [:status, :discard_reason])
      |> validate_required([:status])
      |> validate_length(:discard_reason, max: 255)

    if get_field(changeset, :status) == :discarded do
      validate_required(changeset, [:discard_reason], message: "indica el motivo del descarte")
    else
      put_change(changeset, :discard_reason, nil)
    end
  end
end
