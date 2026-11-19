defmodule Caseo.Repo.Migrations.AddSecondFactor do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_secret, :text
      add :totp_last_step, :bigint
      add :recovery_code_hashes, {:array, :binary}, null: false, default: []
      add :second_factor_attempts, :integer, null: false, default: 0
      add :second_factor_window_at, :utc_datetime
    end
  end
end
