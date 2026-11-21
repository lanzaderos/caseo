defmodule Caseo.Properties.Photo do
  @moduledoc "A private image belonging to a property or one of its rooms."

  use Ecto.Schema

  alias Caseo.Properties.Property
  alias Caseo.Properties.Room

  schema "property_photos" do
    belongs_to :property, Property
    belongs_to :room, Room
    field :content_type, :string
    field :data, :binary, load_in_query: false
    field :cover, :boolean, default: false

    timestamps(type: :utc_datetime)
  end
end
