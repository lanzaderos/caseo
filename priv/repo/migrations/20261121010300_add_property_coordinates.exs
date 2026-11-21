defmodule Caseo.Repo.Migrations.AddPropertyCoordinates do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :latitude, :float
      add :longitude, :float
    end
  end
end
