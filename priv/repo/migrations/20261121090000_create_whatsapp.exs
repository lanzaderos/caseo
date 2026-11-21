defmodule Caseo.Repo.Migrations.CreateWhatsapp do
  use Ecto.Migration

  def change do
    # One linked number per owner. `provider` lets each owner move from
    # whatsmeow to the Cloud API independently.
    create table(:whatsapp_accounts) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :session_id, :string, null: false
      add :phone, :string
      add :linked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:whatsapp_accounts, [:owner_id])
    create unique_index(:whatsapp_accounts, [:provider, :session_id])

    create table(:whatsapp_messages) do
      add :account_id, references(:whatsapp_accounts, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :contact_phone, :string, null: false
      add :contact_name, :string
      add :direction, :string, null: false
      # Outbound only: a reply inside the 24-hour window, or a message we start
      # (a template under the Cloud API).
      add :origin, :string
      add :type, :string, null: false, default: "text"
      add :body, :text
      add :sent_at, :utc_datetime, null: false
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:whatsapp_messages, [:account_id, :external_id])
    create index(:whatsapp_messages, [:account_id, :contact_phone, :sent_at])
  end
end
