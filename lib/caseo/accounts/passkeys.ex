defmodule Caseo.Accounts.Passkeys do
  @moduledoc "Passkey enrollment, management and authentication."

  import Ecto.Query
  alias Caseo.{Accounts, Repo}
  alias Caseo.Accounts.{Passkey, User}

  @timeout 120
  @verification "required"
  @algorithms [-7, -257]
  @invalid {:error, :invalid}

  def enabled?, do: not is_nil(Application.get_env(:caseo, :passkeys))

  def list(%User{id: user_id}) do
    Repo.all(from p in Passkey, where: p.user_id == ^user_id, order_by: [asc: p.id])
  end

  def registration_options(user, binding) do
    challenge = issue_challenge("register", binding)

    Map.merge(options(challenge), %{
      rp: %{id: challenge.rp_id, name: "Caseo"},
      user: %{id: encode(handle(user)), name: user.email, displayName: user.email},
      pubKeyCredParams: Enum.map(@algorithms, &%{type: "public-key", alg: &1}),
      authenticatorSelection: %{residentKey: "required", userVerification: @verification},
      attestation: "none",
      excludeCredentials: Enum.map(list(user), &descriptor/1)
    })
  end

  def authentication_options(binding) do
    challenge = issue_challenge("authenticate", binding)

    Map.merge(options(challenge), %{rpId: challenge.rp_id, userVerification: @verification})
  end

  def register(session, binding, params) do
    with {:ok, challenge} <- consume_challenge("register", binding, params),
         {:ok, data} <- decode_field(params, "clientDataJSON", 8192),
         {:ok, attestation} <- decode_field(params, "attestationObject", 32_768),
         {:ok, credential} <- verify_registration(attestation, data, challenge),
         %{3 => alg} = key when alg in @algorithms <- credential.credential_public_key,
         {:ok, encoded_id} <- decode_field(params, "credentialId", 2048),
         true <- encoded_id == credential.credential_id do
      with_recent_user(session, fn user ->
        %Passkey{
          user_id: user.id,
          credential_id: encoded_id,
          public_key: :erlang.term_to_binary(key)
        }
        |> Passkey.name_changeset(params)
        |> Repo.insert()
      end)
    else
      _ -> @invalid
    end
  end

  def authenticate(binding, expected_user, params) do
    with {:ok, challenge} <- consume_challenge("authenticate", binding, params),
         {:ok, id} <- decode_field(params, "credentialId", 2048),
         %{user_id: user_id} <- Repo.get_by(Passkey, credential_id: id),
         true <- is_nil(expected_user) or expected_user == user_id do
      Repo.transact(fn -> authenticate_credential(user_id, id, params, challenge) end)
    else
      _ -> @invalid
    end
  end

  def rename(session, id, params) do
    with_recent_user(session, fn user ->
      with {:ok, passkey} <- get_owned(user, id) do
        passkey |> Passkey.name_changeset(params) |> Repo.update()
      end
    end)
  end

  def revoke(session, id) do
    with_recent_user(session, fn user ->
      with {:ok, passkey} <- get_owned(user, id), do: Repo.delete(passkey)
    end)
  end

  defp get_owned(user, id) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(id),
         %Passkey{} = passkey <- Repo.get_by(Passkey, id: id, user_id: user.id) do
      {:ok, passkey}
    else
      _ -> @invalid
    end
  end

  defp with_recent_user(session, fun) do
    Repo.transact(fn ->
      with true <- is_binary(session),
           {%User{id: id}, _} <- Accounts.get_user_by_session_token(session),
           %User{} <- Accounts.lock_user(id),
           {%User{} = user, _} <- Accounts.get_user_by_session_token(session),
           true <- Accounts.sudo_mode?(user, -10) do
        fun.(user)
      else
        _ -> {:error, :reauthenticate}
      end
    end)
  end

  defp verify_registration(attestation, data, challenge) do
    with :ok <- same_origin_client_data(data),
         {:ok, {%{attested_credential_data: %{} = credential}, _}} <-
           Wax.register(attestation, data, challenge) do
      {:ok, credential}
    end
  rescue
    # Wax may raise on malformed authenticator data.
    _ -> @invalid
  end

  defp authenticate_credential(user_id, id, params, challenge) do
    with %User{confirmed_at: confirmed_at} = user when not is_nil(confirmed_at) <-
           Accounts.lock_user(user_id),
         %Passkey{public_key: key} <- Repo.get_by(Passkey, credential_id: id, user_id: user_id),
         :ok <- verify_assertion(params, user, id, key, challenge) do
      # A verified passkey satisfies the account's second-factor policy.
      {:ok, {user, Accounts.generate_user_session_token(user)}}
    else
      _ -> @invalid
    end
  end

  defp verify_assertion(params, user, id, public_key, challenge) do
    with {:ok, user_handle} <- decode_field(params, "userHandle", 128),
         true <- user_handle == handle(user),
         {:ok, data} <- decode_field(params, "clientDataJSON", 8192),
         :ok <- same_origin_client_data(data),
         {:ok, auth_data} <- decode_field(params, "authenticatorData", 8192),
         {:ok, signature} <- decode_field(params, "signature", 2048),
         key = :erlang.binary_to_term(public_key, [:safe]),
         {:ok, _auth_data} <-
           Wax.authenticate(id, auth_data, signature, data, challenge, [{id, key}]) do
      :ok
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  defp same_origin_client_data(data) do
    case Jason.decode(data) do
      {:ok, %{} = decoded} ->
        if Map.get(decoded, "crossOrigin", false) == false, do: :ok, else: @invalid

      _ ->
        @invalid
    end
  end

  defp issue_challenge(purpose, binding) do
    challenge = new_challenge(purpose)
    now = DateTime.utc_now(:second)

    Repo.delete_all(from c in "passkey_challenges", where: c.expires_at <= ^now)

    Repo.insert_all(
      "passkey_challenges",
      [
        %{
          bytes: challenge.bytes,
          binding: binding,
          purpose: purpose,
          expires_at: DateTime.add(now, @timeout)
        }
      ],
      conflict_target: [:binding, :purpose],
      on_conflict: {:replace, [:bytes, :expires_at]}
    )

    challenge
  end

  defp consume_challenge(purpose, binding, params) do
    with true <- is_binary(binding),
         {:ok, <<_::256>> = bytes} <- decode_field(params, "challenge", 64),
         now = DateTime.utc_now(:second),
         {1, _} <-
           Repo.delete_all(
             from c in "passkey_challenges",
               where: c.bytes == ^bytes and c.binding == ^binding and c.purpose == ^purpose,
               where: c.expires_at > ^now
           ) do
      {:ok, %{new_challenge(purpose) | bytes: bytes}}
    else
      _ -> @invalid
    end
  end

  defp new_challenge(purpose) do
    opts =
      Application.fetch_env!(:caseo, :passkeys)
      |> Keyword.merge(user_verification: @verification, timeout: @timeout)

    case purpose do
      "register" ->
        Wax.new_registration_challenge(Keyword.put(opts, :trusted_attestation_types, [:none]))

      "authenticate" ->
        Wax.new_authentication_challenge(opts)
    end
  end

  defp options(challenge), do: %{challenge: encode(challenge.bytes), timeout: @timeout * 1000}

  defp descriptor(passkey), do: %{type: "public-key", id: encode(passkey.credential_id)}

  defp handle(user), do: Ecto.UUID.dump!(user.passkey_handle)

  defp encode(value), do: Base.url_encode64(value, padding: false)

  defp decode_field(params, name, max) do
    case params[name] do
      value when is_binary(value) and byte_size(value) <= max ->
        Base.url_decode64(value, padding: false)

      _ ->
        @invalid
    end
  end
end
