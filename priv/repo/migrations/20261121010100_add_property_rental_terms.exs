defmodule Caseo.Repo.Migrations.AddPropertyRentalTerms do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :rental_term, :string
      add :available_until, :date
      add :minimum_months, :integer
      add :maximum_months, :integer
      add :for_students, :boolean, default: false, null: false
      add :academic_year, :string
    end
  end
end
