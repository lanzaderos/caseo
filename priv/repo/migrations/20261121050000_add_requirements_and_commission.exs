defmodule Caseo.Repo.Migrations.AddRequirementsAndCommission do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :requirements, :map
      add :commission, :map
    end

    alter table(:rooms) do
      add :custom_terms, :boolean, null: false, default: false
      add :requirements, :map
      add :commission, :map
    end

    alter table(:lead_interests) do
      add :checks, :map, null: false, default: %{}
    end
  end
end
