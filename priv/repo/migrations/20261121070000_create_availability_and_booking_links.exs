defmodule Caseo.Repo.Migrations.CreateAvailabilityAndBookingLinks do
  use Ecto.Migration

  def change do
    create table(:availability_windows) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :starts_at, :naive_datetime, null: false
      add :ends_at, :naive_datetime, null: false
      add :slot_minutes, :integer, null: false, default: 30

      timestamps(type: :utc_datetime)
    end

    create index(:availability_windows, [:owner_id, :starts_at])
    create constraint(:availability_windows, :ends_after_start, check: "ends_at > starts_at")
    create constraint(:availability_windows, :positive_slot, check: "slot_minutes > 0")

    create table(:booking_links) do
      add :interest_id, references(:lead_interests, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :visit_id, references(:visits, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_links, [:token_hash])
    create index(:booking_links, [:interest_id])
  end
end
