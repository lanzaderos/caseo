defmodule Caseo.Properties.Property do
  @moduledoc "A rental property owned by a Caseo account."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "properties" do
    belongs_to :owner, Caseo.Accounts.User
    field :name, :string
    field :rent_cents, :integer
    field :rent, :string, virtual: true
    field :available_on, :date
    field :archived_at, :utc_datetime
    field :listing_source, :string
    field :listing_external_id, :string
    field :listing_url, :string
    field :location, :string
    field :area_m2, :integer

    timestamps(type: :utc_datetime)
  end

  @idealista_url ~r"\Ahttps://www\.idealista\.com/(?:[a-z]{2}/)?inmueble/([0-9]{1,20})/?(?:[?#].*)?\z"

  @doc """
  Validates a listing imported from a portal. The source and external ID are
  derived from the URL on the server, never taken from the client.
  """
  @spec import_changeset(t(), map()) :: Ecto.Changeset.t()
  def import_changeset(property, attrs) do
    property
    |> changeset(Map.take(attrs, ["name", "rent"]))
    |> cast(attrs, [:listing_url, :location, :area_m2])
    |> validate_required([:listing_url])
    |> validate_length(:listing_url, max: 2048)
    |> validate_length(:location, max: 255)
    |> validate_number(:area_m2, greater_than: 0, less_than: 100_000)
    |> put_listing_identity()
    |> unique_constraint([:owner_id, :listing_source, :listing_external_id])
  end

  @doc "Returns the Idealista listing ID in a listing URL, or `nil`."
  @spec idealista_id(term()) :: String.t() | nil
  def idealista_id(url) when is_binary(url) do
    case Regex.run(@idealista_url, url) do
      [_, id] -> id
      nil -> nil
    end
  end

  def idealista_id(_url), do: nil

  defp put_listing_identity(changeset) do
    url = get_field(changeset, :listing_url)

    case idealista_id(url) do
      nil ->
        add_error(changeset, :listing_url, "debe ser la ficha de un anuncio de Idealista")

      id ->
        changeset
        |> put_change(:listing_source, "idealista")
        |> put_change(:listing_external_id, id)
        |> put_change(:listing_url, "https://www.idealista.com/inmueble/#{id}/")
    end
  end

  @doc "Validates editable data and converts the monthly rent to integer cents."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(property, attrs) do
    %{property | rent: formatted_rent(property)}
    |> cast(attrs, [:name, :rent, :available_on])
    |> validate_required([:name, :rent])
    |> validate_length(:name, max: 255)
    |> validate_format(:rent, ~r/\A[0-9]{1,12}(?:[,.][0-9]{1,2})?\z/,
      message: "introduce un importe con hasta dos decimales"
    )
    |> put_rent_cents()
  end

  @doc "Formats the monthly rent in euros, with a decimal comma."
  @spec formatted_rent(t()) :: String.t() | nil
  def formatted_rent(%__MODULE__{rent_cents: nil}), do: nil

  def formatted_rent(%__MODULE__{rent_cents: cents}) do
    decimals = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{div(cents, 100)},#{decimals}"
  end

  defp put_rent_cents(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp put_rent_cents(changeset) do
    [euros | decimals] = changeset |> get_field(:rent) |> String.split([",", "."])
    fraction = decimals |> List.first("0") |> String.pad_trailing(2, "0")
    cents = String.to_integer(euros) * 100 + String.to_integer(fraction)

    if cents > 0 do
      put_change(changeset, :rent_cents, cents)
    else
      add_error(changeset, :rent, "debe ser mayor que cero")
    end
  end
end
