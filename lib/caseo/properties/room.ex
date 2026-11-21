defmodule Caseo.Properties.Room do
  @moduledoc "An individually rentable room within a property."

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Commission
  alias Caseo.Properties.Offer
  alias Caseo.Properties.Property
  alias Caseo.Properties.Requirements

  @type t :: %__MODULE__{}

  schema "rooms" do
    belongs_to :property, Property
    field :name, :string
    field :description, :string
    field :rent_cents, :integer
    field :rent, :string, virtual: true
    field :available_on, :date
    field :rental_term, Ecto.Enum, values: [:long_term, :temporary]
    field :available_until, :date
    field :minimum_months, :integer
    field :maximum_months, :integer
    field :for_students, :boolean, default: false
    field :academic_year, :string
    field :custom_terms, :boolean, default: false
    embeds_one :requirements, Requirements, on_replace: :update, defaults_to_struct: true
    embeds_one :commission, Commission, on_replace: :update, defaults_to_struct: true

    timestamps(type: :utc_datetime)
  end

  def changeset(room, attrs) do
    %{room | rent: Offer.format_amount(room.rent_cents)}
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 5_000)
    |> Offer.change_amount(attrs, :rent, :rent_cents)
    |> Offer.change_rental(attrs)
    |> change_terms(attrs)
  end

  # A room overrides the property's requirements and commission only when the
  # owner asks for it; otherwise its stored terms are left untouched and unused.
  defp change_terms(changeset, attrs) do
    changeset = cast(changeset, attrs, [:custom_terms])

    if get_field(changeset, :custom_terms) do
      changeset
      |> cast_embed(:requirements, with: &Requirements.changeset(&1, &2, :rooms))
      |> cast_embed(:commission, with: &Commission.changeset(&1, &2, :rooms))
    else
      changeset
    end
  end
end
