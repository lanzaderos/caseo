defmodule Caseo.Repo.Migrations.AddPasskeys do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :passkey_handle, :uuid, null: false, default: fragment("gen_random_uuid()")
    end

    create table(:user_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:user_passkeys, [:user_id])
    create unique_index(:user_passkeys, [:credential_id])

    create table(:passkey_challenges, primary_key: false) do
      add :bytes, :binary, primary_key: true
      add :binding, :binary, null: false
      add :purpose, :string, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create unique_index(:passkey_challenges, [:binding, :purpose])
    create index(:passkey_challenges, [:expires_at])
  end
end
