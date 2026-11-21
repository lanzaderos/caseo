defmodule Caseo.Repo.Migrations.CreateLeads do
  use Ecto.Migration

  def change do
    create table(:leads) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :phone, :string, null: false
      add :email, :string
      add :source, :string, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:leads, [:owner_id, :phone])

    create table(:lead_interests) do
      add :lead_id, references(:leads, on_delete: :delete_all), null: false
      add :property_id, references(:properties, on_delete: :delete_all), null: false

      add :room_id,
          references(:rooms, with: [property_id: :property_id], on_delete: :delete_all)

      add :status, :string, null: false, default: "new"
      add :discard_reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lead_interests, [:lead_id, :property_id, :room_id],
             nulls_distinct: false
           )

    create index(:lead_interests, [:property_id])
  end
end
