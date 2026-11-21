defmodule Caseo.Properties.ListingImport do
  @moduledoc """
  Raw data read by the browser extension from a portal listing. It stays
  pending until the owner reviews it and creates or links a property.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Property

  @type t :: %__MODULE__{}

  @text_limit 500
  @list_limit 200
  @image_limit 50
  @image_url ~r"\Ahttps://img[0-9]*\.idealista\.com/[^\s\"'<>]{1,1000}\z"

  schema "listing_imports" do
    belongs_to :owner, Caseo.Accounts.User
    belongs_to :property, Property
    field :source, :string
    field :external_id, :string
    field :url, :string
    field :raw, :map
    field :status, Ecto.Enum, values: [:pending, :confirmed, :discarded], default: :pending

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an import from the extension payload. Only known keys are kept, each
  bounded in size, and image URLs are limited to Idealista's image hosts.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(listing_import, params) do
    url = Map.get(params, "url")

    listing_import
    |> change(raw: sanitize(params))
    |> put_identity(url)
  end

  @doc "Image URLs of the listing that Caseo is allowed to download."
  @spec image_urls(t()) :: [String.t()]
  def image_urls(%__MODULE__{raw: raw}), do: Map.get(raw, "images", [])

  @doc "Whether a URL is one of the listing's downloadable images."
  @spec image_url?(t(), term()) :: boolean()
  def image_url?(listing_import, url), do: url in image_urls(listing_import)

  defp put_identity(changeset, url) do
    case Property.idealista_id(url) do
      nil ->
        add_error(changeset, :url, "debe ser la ficha de un anuncio de Idealista")

      id ->
        change(changeset,
          source: "idealista",
          external_id: id,
          url: "https://www.idealista.com/inmueble/#{id}/"
        )
    end
  end

  defp sanitize(params) do
    %{
      "title" => text(params["title"]),
      "price" => text(params["price"]),
      "location" => text(params["location"]),
      "description" => text(params["description"], 20_000),
      "features" => texts(params["features"]),
      "details" => texts(params["details"]),
      "address" => texts(params["address"]),
      "images" => images(params["images"])
    }
  end

  # Idealista repeats each photo in several sizes and formats, e.g.
  # .../blur/340_280_mq/0/id.pro.es.image.master/c9/00/35/1494379906.webp.
  # Keep one URL per photo, in page order: the largest size, preferring JPEG.
  @image_id ~r"/([0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/\d+)\.(jpe?g|webp|png)\z"
  @sizes ~w(1500_80_mq WEB_DETAIL_TOP-L-L WEB_DETAIL_TOP-L-P WEB_DETAIL-M-L)

  defp images(urls) when is_list(urls) do
    urls
    |> Enum.take(1_000)
    |> Enum.filter(&(is_binary(&1) and &1 =~ @image_url))
    |> Enum.flat_map(fn url ->
      case Regex.run(@image_id, url) do
        [_, id, format] -> [{id, url, image_rank(url, format)}]
        nil -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {_id, variants} -> Enum.min_by(variants, &elem(&1, 2)) end)
    |> Enum.sort_by(fn {id, _url, _rank} -> Enum.find_index(urls, &String.contains?(&1, id)) end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.take(@image_limit)
  end

  defp images(_urls), do: []

  defp image_rank(url, format) do
    size = Enum.find_index(@sizes, &String.contains?(url, "/#{&1}/")) || length(@sizes)
    {size, if(format in ["jpg", "jpeg"], do: 0, else: 1)}
  end

  defp text(value, limit \\ @text_limit)

  defp text(value, limit) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, limit) do
      "" -> nil
      text -> text
    end
  end

  defp text(_value, _limit), do: nil

  defp texts(values) when is_list(values) do
    values |> Enum.take(@list_limit) |> Enum.map(&text/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp texts(_values), do: []
end
