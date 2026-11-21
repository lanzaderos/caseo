defmodule Caseo.Repo.Migrations.AddWeeklyAvailability do
  use Ecto.Migration

  def change do
    alter table(:availability_windows) do
      add :weekly, :boolean, null: false, default: false
      add :repeat_until, :date
    end
  end
end
