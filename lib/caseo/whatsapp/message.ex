defmodule Caseo.Whatsapp.Message do
  @moduledoc """
  A WhatsApp message in Caseo's own format, independent of the provider.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @types [:text, :image, :video, :audio, :document, :location, :other]

  schema "whatsapp_messages" do
    belongs_to :account, Caseo.Whatsapp.Account
    field :external_id, :string
    field :contact_phone, :string
    field :contact_name, :string
    field :direction, Ecto.Enum, values: [:inbound, :outbound]
    field :origin, Ecto.Enum, values: [:reply, :initiated]
    field :type, Ecto.Enum, values: @types, default: :text
    field :body, :string
    field :sent_at, :utc_datetime
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Message types."
  def types, do: @types

  @doc "Short text for the message, with a label for media without caption."
  def preview(%__MODULE__{body: body}) when body not in [nil, ""], do: body
  def preview(%__MODULE__{type: :image}), do: "📷 Foto"
  def preview(%__MODULE__{type: :video}), do: "🎥 Vídeo"
  def preview(%__MODULE__{type: :audio}), do: "🎤 Audio"
  def preview(%__MODULE__{type: :document}), do: "📄 Documento"
  def preview(%__MODULE__{type: :location}), do: "📍 Ubicación"
  def preview(%__MODULE__{}), do: "Mensaje no compatible"
end
