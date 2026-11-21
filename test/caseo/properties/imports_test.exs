defmodule Caseo.Properties.ImportsTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Properties
  alias Caseo.Properties.Imports
  alias Caseo.Properties.ListingImages
  alias Caseo.Properties.Photos
  alias Caseo.Repo

  @image "https://img4.idealista.com/blur/WEB_DETAIL_TOP-L-L/0/id.pro.es.image.master/fa/2f/11/1494055208.jpg"
  @jpeg <<255, 216, 255, 224>> <> :binary.copy(<<0>>, 64)

  @payload %{
    "url" => "https://www.idealista.com/inmueble/555/?xtmc=1",
    "title" => "Piso en alquiler en calle Mayor",
    "price" => "900 €/mes",
    "features" => ["70 m²"],
    "address" => ["Calle Mayor", "Barrio Sol", "Madrid", "Madrid capital, Madrid"],
    "images" => [@image, "https://evil.example/x.jpg"],
    "owner_id" => 999
  }

  @reviewed %{
    "name" => "Piso Mayor",
    "mode" => "rental",
    "rent" => "900",
    "for_students" => "false",
    "street" => "Calle Mayor 3",
    "municipality" => "Madrid",
    "postal_code" => "28013",
    "province" => "Madrid"
  }

  setup do
    scope = user_scope_fixture()
    {:ok, listing_import} = Imports.create(scope, @payload)
    %{scope: scope, listing_import: listing_import}
  end

  test "keeps only known, bounded fields and Idealista images", %{
    scope: scope,
    listing_import: listing_import
  } do
    assert listing_import.owner_id == scope.user.id
    assert listing_import.external_id == "555"
    assert listing_import.url == "https://www.idealista.com/inmueble/555/"
    assert listing_import.raw["images"] == [@image]
    refute Map.has_key?(listing_import.raw, "owner_id")

    assert %{"mode" => "rental", "rent" => "900", "source_url" => url} =
             Imports.preview_params(listing_import)

    assert url == listing_import.url
    assert {:error, changeset} = Imports.create(scope, %{@payload | "url" => "https://x.test/"})
    assert %{url: [_]} = errors_on(changeset)
  end

  # Variants read from a real listing (https://www.idealista.com/inmueble/112450146/).
  test "keeps one image per photo, the largest JPEG, in page order", %{scope: scope} do
    base = "https://img4.idealista.com/blur"
    first = "0/id.pro.es.image.master/11/64/6a/1470392092"
    second = "0/id.pro.es.image.master/f7/4f/ed/1470392063"

    images = [
      "#{base}/340_280_mq/#{first}.webp",
      "#{base}/1500_80_mq/#{first}.webp",
      "#{base}/1500_80_mq/#{first}.jpg",
      "#{base}/WEB_DETAIL_TOP-L-L/#{first}.jpg",
      "#{base}/WEB_DETAIL-M-L/#{second}.jpg",
      "#{base}/340_280_mq/#{second}.webp"
    ]

    {:ok, listing_import} = Imports.create(scope, %{@payload | "images" => images})

    assert listing_import.raw["images"] == [
             "#{base}/1500_80_mq/#{first}.jpg",
             "#{base}/WEB_DETAIL-M-L/#{second}.jpg"
           ]
  end

  test "another owner cannot open or detect the import", %{listing_import: listing_import} do
    other = user_scope_fixture()
    assert {:error, :not_found} = Imports.fetch_pending(other, listing_import.id)
    assert {:ok, other_import} = Imports.create(other, @payload)
    assert Imports.matches(other, other_import) == %{properties: [], rooms: []}
  end

  test "confirm creates a linked draft and copies the authorized images", %{
    scope: scope,
    listing_import: listing_import
  } do
    Req.Test.stub(ListingImages, &Plug.Conn.send_resp(&1, 200, @jpeg))

    assert {:ok, property, 1} =
             Imports.confirm(scope, listing_import, @reviewed, [
               @image,
               "https://evil.example/x.jpg"
             ])

    assert property.status == :draft
    assert property.listing_external_id == "555"
    assert property.source_url == "https://www.idealista.com/inmueble/555/"
    assert property.area_m2 == 70
    assert [_photo] = Photos.list(scope, property.id, nil)
    assert {:error, :not_found} = Imports.fetch_pending(scope, listing_import.id)
    assert %{properties: [match]} = Imports.matches(scope, listing_import)
    assert match.id == property.id
  end

  test "a repeated listing creates a new draft without stealing the link", %{
    scope: scope,
    listing_import: listing_import
  } do
    {:ok, first, 0} = Imports.confirm(scope, listing_import, @reviewed, [])
    {:ok, again} = Imports.create(scope, @payload)

    assert %{properties: [%{id: id}]} = Imports.matches(scope, again)
    assert id == first.id
    assert {:ok, second, 0} = Imports.confirm(scope, again, @reviewed, [])
    assert is_nil(second.listing_external_id)
  end

  test "links the listing to a property or a room of the owner only", %{
    scope: scope,
    listing_import: listing_import
  } do
    {:ok, property} =
      Properties.create_property(
        scope,
        @reviewed
        |> Map.merge(%{
          "mode" => "rooms",
          "rooms" => %{"0" => %{"name" => "A", "rent" => "400", "for_students" => "false"}}
        })
        |> Map.delete("rent")
      )

    [room] = property.rooms
    {:ok, foreign} = Properties.create_property(user_scope_fixture(), @reviewed)

    assert {:error, :not_found} = Imports.link(scope, listing_import, "property:#{foreign.id}")
    assert {:ok, _} = Imports.link(scope, listing_import, "room:#{room.id}")
    assert %{rooms: [%{id: room_id}], properties: []} = Imports.matches(scope, listing_import)
    assert room_id == room.id

    {:ok, again} = Imports.create(scope, @payload)
    assert {:ok, linked} = Imports.link(scope, again, "property:#{property.id}")
    assert linked.source_url == again.url
    assert %{rooms: [], properties: [%{id: property_id}]} = Imports.matches(scope, again)
    assert property_id == property.id
    assert Repo.reload!(property).listing_external_id == "555"
  end
end
