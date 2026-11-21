defmodule Caseo.Repo.Migrations.CreateVisits do
  use Ecto.Migration

  def change do
    create table(:visits) do
      add :interest_id, references(:lead_interests, on_delete: :delete_all), null: false
      add :starts_at, :naive_datetime, null: false
      add :duration_minutes, :integer, null: false, default: 30
      add :status, :string, null: false, default: "scheduled"
      add :notes, :text
      add :reschedules, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:visits, [:interest_id])
    create index(:visits, [:starts_at])
    create constraint(:visits, :positive_duration, check: "duration_minutes > 0")
  end
end
