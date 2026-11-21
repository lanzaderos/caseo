defmodule Caseo.Properties.Property do
  @moduledoc "An individually owned property offered for rent or sale."

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Offer
  alias Caseo.Properties.Room

  @type t :: %__MODULE__{}
  @address_fields [:street, :municipality, :postal_code, :province]

  schema "properties" do
    belongs_to :owner, Caseo.Accounts.User
    has_many :rooms, Room, on_replace: :delete, preload_order: [asc: :id]
    field :name, :string
    field :mode, Ecto.Enum, values: [:rental, :rooms, :sale], default: :rental
    field :rent_cents, :integer
    field :rent, :string, virtual: true
    field :sale_price_cents, :integer
    field :sale_price, :string, virtual: true
    field :street, :string
    field :floor, :string
    field :door, :string
    field :municipality, :string
    field :postal_code, :string
    field :province, :string
    field :latitude, :float
    field :longitude, :float
    field :description, :string
    field :amenities, :string
    field :source_url, :string
    field :available_on, :date
    field :rental_term, Ecto.Enum, values: [:long_term, :temporary]
    field :available_until, :date
    field :minimum_months, :integer
    field :maximum_months, :integer
    field :for_students, :boolean, default: false
    field :academic_year, :string
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
    |> cast(attrs, [:name, :listing_url, :location, :area_m2])
    |> validate_required([:name, :listing_url])
    |> validate_length(:name, max: 255)
    |> change_import_mode(attrs)
    |> change_import_price(attrs)
    |> change_import_address(attrs)
    |> validate_length(:listing_url, max: 2048)
    |> validate_length(:location, max: 255)
    |> validate_number(:area_m2, greater_than: 0, less_than: 100_000)
    |> put_listing_identity()
    |> put_source_url()
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

  # A new import takes its mode from the price (Idealista shows "€/mes" only for
  # rentals). Reimports keep the mode chosen by the owner.
  defp change_import_mode(%{data: %__MODULE__{id: nil}} = changeset, attrs) do
    if Map.get(attrs, "sale_price") in [nil, ""],
      do: put_change(changeset, :mode, :rental),
      else: put_change(changeset, :mode, :sale)
  end

  defp change_import_mode(changeset, _attrs), do: changeset

  defp change_import_price(changeset, attrs) do
    case get_field(changeset, :mode) do
      :rental ->
        changeset
        |> put_change(:rent, formatted_rent(changeset.data))
        |> Offer.change_amount(attrs, :rent, :rent_cents)

      :sale ->
        changeset
        |> put_change(:sale_price, Offer.format_amount(changeset.data.sale_price_cents))
        |> Offer.change_amount(attrs, :sale_price, :sale_price_cents)

      :rooms ->
        changeset
    end
  end

  # The listing prefills the address only while the property has none, so the
  # owner's address (and its map coordinates) survive reimports. Idealista does
  # not publish the postal code; the owner completes it in the form.
  defp change_import_address(changeset, attrs) do
    if Enum.any?(@address_fields, &Map.get(changeset.data, &1)) do
      changeset
    else
      changeset
      |> cast(attrs, [:street, :municipality, :province])
      |> validate_length(:street, max: 255)
      |> validate_length(:municipality, max: 255)
      |> validate_length(:province, max: 255)
    end
  end

  defp put_source_url(changeset) do
    case {changeset.data.source_url, get_field(changeset, :listing_url)} do
      {nil, url} when is_binary(url) -> put_change(changeset, :source_url, url)
      _ -> changeset
    end
  end

  @doc "Validates the address, listing details and fields specific to the chosen mode."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(property, attrs) do
    %{
      property
      | rent: formatted_rent(property),
        sale_price: Offer.format_amount(property.sale_price_cents)
    }
    |> cast(
      attrs,
      @address_fields ++ [:name, :mode, :floor, :door, :description, :amenities, :source_url]
    )
    |> validate_required([:name, :mode])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 10_000)
    |> validate_length(:amenities, max: 5_000)
    |> validate_length(:source_url, max: 2_048)
    |> validate_change(:source_url, &validate_source/2)
    |> validate_address()
    |> change_coordinates(attrs)
    |> change_offer(attrs)
  end

  @doc "Formats the monthly rent in euros, with a decimal comma."
  @spec formatted_rent(t()) :: String.t() | nil
  def formatted_rent(%__MODULE__{rent_cents: cents}), do: Offer.format_amount(cents)

  defp change_coordinates(changeset, attrs) do
    changeset = cast(changeset, attrs, [:latitude, :longitude])
    address_changed? = Enum.any?(@address_fields, &changed?(changeset, &1))
    coordinates_changed? = changed?(changeset, :latitude) || changed?(changeset, :longitude)

    changeset =
      if address_changed? && !coordinates_changed? do
        change(changeset, latitude: nil, longitude: nil)
      else
        changeset
      end

    changeset
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_coordinate_pair()
  end

  defp validate_coordinate_pair(changeset) do
    case {get_field(changeset, :latitude), get_field(changeset, :longitude)} do
      {nil, nil} -> changeset
      {nil, _} -> add_error(changeset, :latitude, "falta la latitud")
      {_, nil} -> add_error(changeset, :longitude, "falta la longitud")
      {_, _} -> validate_required(changeset, @address_fields)
    end
  end

  defp validate_address(changeset) do
    changeset =
      Enum.reduce(@address_fields ++ [:floor, :door], changeset, fn field, result ->
        validate_length(result, field, max: 255)
      end)

    address_present? = Enum.any?(@address_fields ++ [:floor, :door], &get_field(changeset, &1))

    if is_nil(changeset.data.id) || address_present? ||
         Enum.any?(@address_fields, &Map.get(changeset.data, &1)) do
      validate_required(changeset, @address_fields)
    else
      changeset
    end
  end

  defp validate_source(field, url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil, port: 443}}
      when host in ["www.idealista.com", "idealista.com"] ->
        []

      _ ->
        [{field, "introduce un enlace HTTPS de Idealista"}]
    end
  end

  defp change_offer(changeset, attrs) do
    case get_field(changeset, :mode) do
      :rental ->
        changeset
        |> put_change(:sale_price_cents, nil)
        |> Offer.change_amount(attrs, :rent, :rent_cents)
        |> Offer.change_rental(attrs)

      :sale ->
        changeset
        |> put_change(:rent_cents, nil)
        |> Offer.clear_rental()
        |> cast(attrs, [:available_on])
        |> Offer.change_amount(attrs, :sale_price, :sale_price_cents)

      :rooms ->
        changeset
        |> change(rent_cents: nil, sale_price_cents: nil, available_on: nil)
        |> Offer.clear_rental()
        |> cast_assoc(:rooms, required: true, sort_param: :rooms_sort, drop_param: :rooms_drop)

      nil ->
        changeset
    end
  end
end
