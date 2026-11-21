defmodule Caseo.Repo.Migrations.CreateListingImports do
  use Ecto.Migration

  def change do
    # Imported properties start as drafts until the owner marks them ready.
    alter table(:properties) do
      add :status, :string, null: false, default: "ready"
    end

    # A listing can also be linked to a single room.
    alter table(:rooms) do
      add :listing_source, :string
      add :listing_external_id, :string
      add :listing_url, :string, size: 2048
    end

    create index(:rooms, [:listing_source, :listing_external_id])

    # Data read from a portal listing, kept until the owner confirms or discards it.
    create table(:listing_imports) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :external_id, :string, null: false
      add :url, :string, size: 2048, null: false
      add :raw, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :property_id, references(:properties, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:listing_imports, [:owner_id, :inserted_at])
  end
end
