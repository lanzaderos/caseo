defmodule Caseo.Repo.Migrations.ExpandProperties do
  use Ecto.Migration

  def up do
    alter table(:properties) do
      modify :rent_cents, :bigint, null: true
      add :mode, :string, null: false, default: "rental"
      add :sale_price_cents, :bigint
      add :street, :string
      add :floor, :string
      add :door, :string
      add :municipality, :string
      add :postal_code, :string
      add :province, :string
      add :description, :text
      add :amenities, :text
      add :source_url, :text
    end

    create constraint(:properties, :price_matches_mode,
             check: """
             (mode = 'rental' AND rent_cents IS NOT NULL AND sale_price_cents IS NULL)
             OR (mode = 'sale' AND rent_cents IS NULL AND sale_price_cents IS NOT NULL AND sale_price_cents > 0)
             OR (mode = 'rooms' AND rent_cents IS NULL AND sale_price_cents IS NULL)
             """
           )

    create table(:rooms) do
      add :property_id, references(:properties, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :rent_cents, :bigint, null: false
      add :description, :text
      add :available_on, :date
      add :rental_term, :string
      add :available_until, :date
      add :minimum_months, :integer
      add :maximum_months, :integer
      add :for_students, :boolean, null: false, default: false
      add :academic_year, :string
      timestamps(type: :utc_datetime)
    end

    create index(:rooms, [:property_id])
    create constraint(:rooms, :positive_room_rent, check: "rent_cents > 0")
    create unique_index(:rooms, [:id, :property_id])

    create table(:property_photos) do
      add :property_id, references(:properties, on_delete: :delete_all), null: false

      add :room_id,
          references(:rooms, with: [property_id: :property_id], on_delete: :delete_all)

      add :content_type, :string, null: false
      add :data, :binary, null: false
      add :cover, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:property_photos, [:property_id, :room_id])
  end

  def down do
    drop table(:property_photos)
    drop table(:rooms)
    drop constraint(:properties, :price_matches_mode)

    alter table(:properties) do
      modify :rent_cents, :bigint, null: false
      remove :mode
      remove :sale_price_cents
      remove :street
      remove :floor
      remove :door
      remove :municipality
      remove :postal_code
      remove :province
      remove :description
      remove :amenities
      remove :source_url
    end
  end
end
