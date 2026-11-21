defmodule Caseo.Leads.Lead do
  @moduledoc "A person interested in one or more of the owner's properties."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @sources [:idealista, :fotocasa, :pisos_com, :milanuncios, :whatsapp, :other]

  schema "leads" do
    belongs_to :owner, Caseo.Accounts.User
    has_many :interests, Caseo.Leads.Interest, preload_order: [asc: :id]
    field :name, :string
    field :phone, :string
    field :email, :string
    field :source, Ecto.Enum, values: @sources, default: :whatsapp
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Lists the channels a lead can come from, with their labels."
  def source_options do
    [
      {"Idealista", :idealista},
      {"Fotocasa", :fotocasa},
      {"Pisos.com", :pisos_com},
      {"Milanuncios", :milanuncios},
      {"WhatsApp", :whatsapp},
      {"Otro", :other}
    ]
  end

  @doc "Returns the label of a source."
  def source_label(source) do
    Enum.find_value(source_options(), fn {label, value} -> value == source && label end)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(lead, attrs) do
    lead
    |> cast(attrs, [:name, :phone, :email, :source, :notes])
    |> validate_required([:name, :phone, :source])
    |> validate_length(:name, max: 255)
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "introduce un email válido")
    |> validate_length(:notes, max: 10_000)
    |> update_change(:phone, &normalize_phone/1)
    |> validate_format(:phone, ~r/\A\+[1-9][0-9]{7,14}\z/,
      message: "introduce un teléfono válido, con prefijo si no es español"
    )
    |> unique_constraint(:phone,
      name: :leads_owner_id_phone_index,
      message: "ya tienes un interesado con este teléfono"
    )
  end

  @doc """
  Normalizes a phone number to E.164. Nine-digit numbers without a country
  prefix are taken as Spanish.
  """
  # ponytail: Spanish-default heuristic; swap for ex_phone_number if leads go international.
  @spec normalize_phone(String.t()) :: String.t()
  def normalize_phone(phone) do
    digits = String.replace(phone, ~r/[\s().\/-]/, "")

    case digits do
      "+" <> _ -> digits
      "00" <> rest -> "+" <> rest
      <<first, _::binary-size(8)>> when first in ?6..?9 -> "+34" <> digits
      _ -> digits
    end
  end
end
