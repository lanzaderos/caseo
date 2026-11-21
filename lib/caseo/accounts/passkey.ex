defmodule Caseo.Accounts.Passkey do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_passkeys" do
    belongs_to :user, Caseo.Accounts.User
    field :name, :string
    field :credential_id, :binary, redact: true
    field :public_key, :binary, redact: true
    timestamps(type: :utc_datetime)
  end

  def name_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:credential_id)
  end
end
