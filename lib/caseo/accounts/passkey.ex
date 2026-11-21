defmodule Caseo.Accounts.Passkey do
  @moduledoc "Ecto schema for a WebAuthn credential owned by a Caseo user."
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_passkeys" do
    belongs_to :user, Caseo.Accounts.User
    field :name, :string
    field :credential_id, :binary, redact: true
    field :public_key, :binary, redact: true
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc "Trims and validates a passkey name of up to 80 characters."
  @spec name_changeset(t(), map()) :: Ecto.Changeset.t()
  def name_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:credential_id)
  end
end
