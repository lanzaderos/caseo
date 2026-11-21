defmodule Caseo.PropertiesTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Properties

  @attrs %{
    "name" => "Piso Centro",
    "rent" => "875,50",
    "available_on" => "2026-12-01",
    "street" => "Calle Mayor 12",
    "municipality" => "Madrid",
    "postal_code" => "28013",
    "province" => "Madrid"
  }

  test "creates, edits and archives a property within its owner's scope" do
    scope = user_scope_fixture()

    assert {:ok, property} = Properties.create_property(scope, @attrs)
    assert property.owner_id == scope.user.id
    assert property.rent_cents == 87_550
    assert property.available_on == ~D[2026-12-01]

    assert {:ok, updated} =
             Properties.update_property(scope, property.id, %{
               "name" => "Piso Norte",
               "rent" => "900.5",
               "available_on" => ""
             })

    assert updated.name == "Piso Norte"
    assert updated.rent_cents == 90_050
    assert updated.available_on == nil

    assert [active] = Properties.list_properties(scope)
    assert active.id == property.id
    assert Properties.list_properties(scope, :archived) == []
    assert :ok = Properties.archive_property(scope, property.id)
    assert Properties.list_properties(scope) == []
    assert [archived] = Properties.list_properties(scope, :archived)
    assert archived.id == property.id
    assert %DateTime{} = archived.archived_at
    assert {:error, :not_found} = Properties.archive_property(scope, property.id)
  end

  test "rejects invalid editable fields" do
    scope = user_scope_fixture()

    for rent <- ["", "0", "-1", "9,999", "1e3"] do
      assert {:error, changeset} = Properties.create_property(scope, %{@attrs | "rent" => rent})
      assert Keyword.has_key?(changeset.errors, :rent)
    end

    assert {:error, changeset} =
             Properties.create_property(scope, %{@attrs | "name" => " ", "available_on" => "x"})

    assert Keyword.has_key?(changeset.errors, :name)
    assert Keyword.has_key?(changeset.errors, :available_on)
  end

  test "validates address and mode-specific prices and keeps the Idealista reference" do
    scope = user_scope_fixture()
    source_url = "https://www.idealista.com/inmueble/12345678/"

    sale =
      Map.merge(@attrs, %{
        "mode" => "sale",
        "sale_price" => "190000,50",
        "description" => "Salón exterior",
        "amenities" => "Ascensor e internet",
        "source_url" => source_url
      })

    assert {:error, changeset} = Properties.create_property(scope, Map.delete(sale, "street"))
    assert Keyword.has_key?(changeset.errors, :street)

    assert {:error, changeset} =
             Properties.create_property(scope, %{
               sale
               | "source_url" => "https://idealista.com.example/anuncio"
             })

    assert Keyword.has_key?(changeset.errors, :source_url)

    assert {:ok, property} = Properties.create_property(scope, sale)
    assert property.mode == :sale
    assert property.sale_price_cents == 19_000_050
    assert is_nil(property.rent_cents)
    assert property.source_url == source_url

    assert {:ok, updated} =
             Properties.update_property(scope, property.id, %{"sale_price" => "195000"})

    assert updated.sale_price_cents == 19_500_000
    assert :ok = Properties.archive_property(scope, property.id)
    assert Properties.list_properties(scope) == []

    assert {:error, changeset} =
             Properties.create_property(scope, Map.put(@attrs, "mode", "rooms"))

    assert Keyword.has_key?(changeset.errors, :rooms)
  end

  test "legacy properties can be edited before capturing an address" do
    scope = user_scope_fixture()

    property =
      Caseo.Repo.insert!(%Caseo.Properties.Property{
        owner_id: scope.user.id,
        name: "Inmueble anterior",
        rent_cents: 87_550,
        available_on: ~D[2026-12-01]
      })

    assert {:ok, updated} =
             Properties.update_property(scope, property.id, %{"name" => "Inmueble renombrado"})

    assert updated.rent_cents == property.rent_cents
    assert updated.available_on == property.available_on
    assert updated.mode == :rental
    assert is_nil(updated.street)
  end

  test "isolates reads and writes and ignores injected ownership" do
    owner = user_scope_fixture()
    other = user_scope_fixture()

    assert {:ok, property} =
             Properties.create_property(owner, Map.put(@attrs, "owner_id", other.user.id))

    assert property.owner_id == owner.user.id
    assert Properties.list_properties(other) == []
    assert {:error, :not_found} = Properties.fetch_property(other, property.id)
    assert {:error, :not_found} = Properties.fetch_property(owner, "9223372036854775808")
    assert {:error, :not_found} = Properties.update_property(other, property.id, @attrs)
    assert {:error, :not_found} = Properties.archive_property(other, property.id)

    assert {:ok, unchanged} = Properties.fetch_property(owner, property.id)
    assert unchanged.name == @attrs["name"]
    assert unchanged.archived_at == nil

    assert {:ok, updated} =
             Properties.update_property(owner, property.id, %{"owner_id" => other.user.id})

    assert updated.owner_id == owner.user.id
    assert :ok = Properties.archive_property(owner, property.id)
    assert Properties.list_properties(other, :archived) == []
    assert {:error, :not_found} = Properties.fetch_property(other, property.id)
  end
end
