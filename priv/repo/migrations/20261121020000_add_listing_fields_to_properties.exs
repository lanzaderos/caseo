defmodule Caseo.Repo.Migrations.AddListingFieldsToProperties do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :listing_source, :string
      add :listing_external_id, :string
      add :listing_url, :string, size: 2048
      add :location, :string
      add :area_m2, :integer
    end

    # Reimporting the same listing updates the owner's property instead of duplicating it.
    create unique_index(:properties, [:owner_id, :listing_source, :listing_external_id],
             where: "listing_source IS NOT NULL"
           )

    create constraint(:properties, :positive_area, check: "area_m2 IS NULL OR area_m2 > 0")
  end
end
