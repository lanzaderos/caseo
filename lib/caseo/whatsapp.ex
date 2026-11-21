defmodule Caseo.Whatsapp do
  @moduledoc """
  Links each owner's WhatsApp number to Caseo, stores their conversations and
  sends replies through the owner's provider (`Caseo.Whatsapp.Provider`).

  The rest of the app only talks to this module, never to a provider. Every
  function is scoped to the caller: an owner only sees their own messages.

  To reduce the risk of the number being banned, Caseo only writes to people
  who have written first or who are the owner's leads, and the whatsmeow
  sidecar paces and caps sends.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Leads.Lead
  alias Caseo.Repo
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Message

  @reply_window_hours 24

  ## Accounts

  @doc "Returns the owner's WhatsApp account, or `nil` if they never linked one."
  @spec get_account(Scope.t()) :: Account.t() | nil
  def get_account(%Scope{user: %{id: owner_id}}), do: Repo.get_by(Account, owner_id: owner_id)

  @doc """
  Starts linking the owner's number. Creates the account on the configured
  default provider the first time.
  """
  @spec connect(Scope.t()) :: {:ok, Account.t()} | {:error, term()}
  def connect(scope) do
    account = get_account(scope) || create_account!(scope)

    with {:ok, status} <- provider(account).connect(account) do
      {:ok, sync(account, status)}
    end
  end

  @doc "Refreshes the link state of the owner's number from the provider."
  @spec refresh(Scope.t()) :: {:ok, Account.t() | nil} | {:error, term()}
  def refresh(scope) do
    case get_account(scope) do
      nil ->
        {:ok, nil}

      account ->
        with {:ok, status} <- provider(account).status(account), do: {:ok, sync(account, status)}
    end
  end

  @doc "The linking QR code of the owner's number as a PNG."
  @spec qr_image(Scope.t()) :: {:ok, binary()} | :none | {:error, term()}
  def qr_image(scope) do
    case get_account(scope) do
      nil -> :none
      account -> provider(account).qr_image(account)
    end
  end

  @doc "Unlinks the owner's number. Their stored conversations stay."
  @spec disconnect(Scope.t()) :: :ok | {:error, term()}
  def disconnect(scope) do
    with %Account{} = account <- get_account(scope),
         :ok <- provider(account).logout(account) do
      account |> Ecto.Changeset.change(linked_at: nil) |> Repo.update!()
      :ok
    else
      nil -> :ok
      error -> error
    end
  end

  defp create_account!(%Scope{user: %{id: owner_id}}) do
    session_id =
      "u#{owner_id}-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    Repo.insert!(
      %Account{owner_id: owner_id, provider: config(:default_provider), session_id: session_id},
      on_conflict: :nothing,
      conflict_target: :owner_id
    )

    Repo.get_by!(Account, owner_id: owner_id)
  end

  defp sync(account, %{linked: linked, phone: phone}) do
    linked_at =
      cond do
        linked and account.linked_at -> account.linked_at
        linked -> DateTime.utc_now(:second)
        true -> nil
      end

    changes = %{linked_at: linked_at, phone: phone || account.phone}

    if changes == Map.take(account, [:linked_at, :phone]) do
      account
    else
      account = account |> Ecto.Changeset.change(changes) |> Repo.update!()
      broadcast(account.owner_id, {:whatsapp_account, account})
      account
    end
  end

  ## Messages

  @doc """
  Stores an event received on a provider's webhook. Duplicates (same external
  id) are ignored, so providers may retry.
  """
  @spec receive_event(String.t(), [{String.t(), String.t()}], map()) ::
          {:ok, Message.t() | :duplicate} | :ignore | {:error, :unauthorized | :unknown_account}
  def receive_event(provider_name, headers, params) do
    with {:ok, module} <- fetch_provider(provider_name),
         {:ok, session_id, incoming} <- module.parse_event(headers, params),
         %Account{} = account <-
           Repo.get_by(Account, provider: provider_name, session_id: session_id) ||
             {:error, :unknown_account} do
      store(account, %{
        external_id: incoming.external_id,
        contact_phone: incoming.contact_phone,
        contact_name: incoming.contact_name,
        direction: if(incoming.from_me, do: :outbound, else: :inbound),
        type: incoming.type,
        body: incoming.body,
        sent_at: incoming.sent_at
      })
    end
  end

  @doc """
  Sends a text to `phone` from the owner's number. Caseo only writes to people
  who have written to the owner before or who are among their leads.
  """
  @spec send_text(Scope.t(), String.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :not_linked | :unknown_contact | :empty | term()}
  def send_text(scope, phone, text) do
    phone = Lead.normalize_phone(phone)
    text = String.trim(text)

    with %Account{} = account <- get_account(scope),
         true <- Account.linked?(account) || {:error, :not_linked},
         true <- text != "" || {:error, :empty},
         true <- known_contact?(account, phone) || {:error, :unknown_contact},
         {:ok, sent} <- provider(account).send_text(account, phone, text) do
      store(account, %{
        external_id: sent.external_id,
        contact_phone: phone,
        direction: :outbound,
        origin: origin(account, phone),
        type: :text,
        body: text,
        sent_at: sent.sent_at
      })
      |> case do
        {:ok, %Message{} = message} ->
          {:ok, message}

        {:ok, :duplicate} ->
          {:ok, Repo.get_by!(Message, account_id: account.id, external_id: sent.external_id)}
      end
    else
      nil -> {:error, :not_linked}
      error -> error
    end
  end

  defp known_contact?(account, phone) do
    Repo.exists?(
      from m in Message,
        where:
          m.account_id == ^account.id and m.contact_phone == ^phone and m.direction == :inbound
    ) or
      Repo.exists?(from l in Lead, where: l.owner_id == ^account.owner_id and l.phone == ^phone)
  end

  # A reply inside the 24-hour window after the contact's last message;
  # otherwise we start the conversation (a template under the Cloud API).
  defp origin(account, phone) do
    since = DateTime.add(DateTime.utc_now(), -@reply_window_hours, :hour)

    recent? =
      Repo.exists?(
        from m in Message,
          where:
            m.account_id == ^account.id and m.contact_phone == ^phone and
              m.direction == :inbound and m.sent_at >= ^since
      )

    if recent?, do: :reply, else: :initiated
  end

  defp store(account, attrs) do
    message = struct(%Message{account_id: account.id}, attrs)

    case Repo.insert(message, on_conflict: :nothing, conflict_target: [:account_id, :external_id]) do
      {:ok, %Message{id: nil}} ->
        {:ok, :duplicate}

      {:ok, message} ->
        broadcast(account.owner_id, {:whatsapp_message, message})
        {:ok, message}
    end
  end

  ## Realtime

  @doc "Subscribes the caller to the owner's WhatsApp events."
  @spec subscribe(Scope.t()) :: :ok
  def subscribe(%Scope{user: %{id: owner_id}}),
    do: Phoenix.PubSub.subscribe(Caseo.PubSub, topic(owner_id))

  defp broadcast(owner_id, event),
    do: Phoenix.PubSub.broadcast(Caseo.PubSub, topic(owner_id), event)

  defp topic(owner_id), do: "whatsapp:#{owner_id}"

  ## Providers

  defp provider(%Account{provider: name}) do
    {:ok, module} = fetch_provider(name)
    module
  end

  defp fetch_provider(name) do
    case Map.fetch(config(:providers), name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_account}
    end
  end

  defp config(key), do: :caseo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
