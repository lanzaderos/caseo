defmodule Caseo.Whatsapp.Account do
  @moduledoc "The WhatsApp number an owner links to Caseo, and the provider that serves it."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "whatsapp_accounts" do
    belongs_to :owner, Caseo.Accounts.User
    field :provider, :string
    # The provider's handle for this number (a whatsmeow session, a Cloud API
    # phone number ID…). Never shown to the owner.
    field :session_id, :string
    field :phone, :string
    field :linked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Whether the number is linked and can send and receive."
  def linked?(%__MODULE__{linked_at: linked_at}), do: not is_nil(linked_at)
  def linked?(nil), do: false
end
