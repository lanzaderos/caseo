defmodule Caseo.Properties.Room do
  @moduledoc "An individually rentable room within a property."

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Offer
  alias Caseo.Properties.Property

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
    field :listing_source, :string
    field :listing_external_id, :string
    field :listing_url, :string

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
  end
end
