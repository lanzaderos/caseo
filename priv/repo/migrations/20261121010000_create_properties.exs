defmodule Caseo.Repo.Migrations.CreateProperties do
  use Ecto.Migration

  def change do
    create table(:properties) do
      add :owner_id, references(:users), null: false
      add :name, :string, null: false
      add :rent_cents, :bigint, null: false
      add :available_on, :date
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:properties, [:owner_id, :archived_at, :id])
    create constraint(:properties, :positive_rent, check: "rent_cents > 0")
  end
end
