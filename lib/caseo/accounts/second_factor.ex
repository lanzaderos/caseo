defmodule Caseo.Accounts.SecondFactor do
  @moduledoc """
  Account policy and credential lifecycle for TOTP and recovery codes.
  """

  import Ecto.Query
  alias Caseo.{Accounts, Repo}
  alias Caseo.Accounts.{TOTP, User, UserToken}
  alias CaseoWeb.Endpoint

  @challenge_context "second_factor"
  @challenge_minutes 5
  @max_attempts 5
  @window_seconds 300
  @setup_seconds 600

  def enabled?(%User{totp_secret: secret}), do: is_binary(secret)

  @doc """
  A passkey may satisfy the second factor only after the server verifies its
  assertion and user-verification flag. Callers must derive the method from
  verified credentials, never from request parameters.
  """
  def required?(%User{}, :user_verified_passkey), do: false
  def required?(%User{} = user, _method), do: enabled?(user)

  @doc """
  Starts a login after the caller validates a primary credential.
  """
  def start_login(%User{} = verified_user, method) when method in [:magic_link, :password] do
    transact(fn ->
      case Accounts.lock_user(verified_user.id) do
        %User{email: email, hashed_password: hash, confirmed_at: confirmed_at} = user
        when email == verified_user.email and hash == verified_user.hashed_password and
               not is_nil(confirmed_at) ->
          issue_login(user, method)

        _ ->
          {:error, :invalid}
      end
    end)
  end

  defp issue_login(user, method) do
    if required?(user, method) do
      Repo.delete_all(
        from t in UserToken,
          where: t.user_id == ^user.id and t.context == @challenge_context,
          where: t.inserted_at <= ago(^@challenge_minutes, "minute")
      )

      {challenge, token} = UserToken.build_email_token(user, @challenge_context)
      Repo.insert!(token)
      {:challenge, challenge}
    else
      {:session, Accounts.generate_user_session_token(user)}
    end
  end

  def pending?(challenge), do: challenge && Repo.exists?(challenge_query(challenge))

  def cancel(challenge) when is_binary(challenge) do
    Repo.delete_all(challenge_query(challenge))
    :ok
  end

  def cancel(_challenge), do: :ok

  def complete_login(challenge, code) when is_binary(challenge) and is_binary(code) do
    query = challenge_query(challenge)

    transact(fn ->
      with user_id when not is_nil(user_id) <- Repo.one(from t in query, select: t.user_id),
           %User{} = user <- Accounts.lock_user(user_id),
           %UserToken{sent_to: email} = token <- Repo.one(query),
           true <- user.email == email and enabled?(user),
           {:ok, user} <- consume_attempt(user),
           {:ok, changes} <- verify_factor(user, code),
           {1, _} <- Repo.delete_all(from t in UserToken, where: t.id == ^token.id) do
        update!(user, Map.merge(changes, reset_attempts()))
        {:session, user, Accounts.generate_user_session_token(user)}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :expired}
      end
    end)
  end

  def setup(session) do
    secret = :crypto.strong_rand_bytes(20)
    ticket = Phoenix.Token.encrypt(Endpoint, "totp setup", {hash(session), secret})
    {Base.encode32(secret, padding: false), ticket}
  end

  def enable(session, ticket, code) when is_binary(ticket) and is_binary(code) do
    transact(fn ->
      with {:ok, user} <- recent_user(session),
           session_hash = hash(session),
           false <- enabled?(user),
           {:ok, {^session_hash, secret}} <-
             Phoenix.Token.decrypt(Endpoint, "totp setup", ticket, max_age: @setup_seconds),
           {:ok, user} <- consume_attempt(user),
           step when is_integer(step) <- TOTP.matching_step(secret, code, nil, now()) do
        enable_factor(user, secret, step)
      else
        {:error, :reauthenticate} = error -> error
        {:error, :rate_limited} = error -> error
        _ -> {:error, :invalid}
      end
    end)
  end

  defp enable_factor(user, secret, step) do
    codes = Enum.map(1..10, fn _ -> Base.encode16(:crypto.strong_rand_bytes(12)) end)

    update!(
      user,
      Map.merge(reset_attempts(), %{
        totp_secret: Phoenix.Token.encrypt(Endpoint, "totp secret", {user.id, secret}),
        totp_last_step: step,
        recovery_code_hashes: Enum.map(codes, &hash/1)
      })
    )

    {:ok, codes, revoke_tokens(user)}
  end

  def disable(session) do
    transact(fn ->
      with {:ok, user} <- recent_user(session),
           true <- enabled?(user) do
        update!(
          user,
          Map.merge(reset_attempts(), %{
            totp_secret: nil,
            totp_last_step: nil,
            recovery_code_hashes: []
          })
        )

        {:ok, revoke_tokens(user)}
      else
        false -> {:error, :invalid}
        error -> error
      end
    end)
  end

  defp verify_factor(user, code) do
    code = String.trim(code)

    case byte_size(code) do
      6 ->
        with {:ok, {id, secret}} when id == user.id <-
               Phoenix.Token.decrypt(Endpoint, "totp secret", user.totp_secret,
                 max_age: :infinity
               ),
             step when is_integer(step) <-
               TOTP.matching_step(secret, code, user.totp_last_step, now()) do
          {:ok, %{totp_last_step: step}}
        else
          _ -> {:error, :invalid}
        end

      24 ->
        digest = hash(String.upcase(code))

        case Enum.split_with(user.recovery_code_hashes, &Plug.Crypto.secure_compare(&1, digest)) do
          {[], _remaining} -> {:error, :invalid}
          {_, remaining} -> {:ok, %{recovery_code_hashes: remaining}}
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp recent_user(session) when is_binary(session) do
    with {%User{id: id}, _} <- Accounts.get_user_by_session_token(session),
         %User{} <- Accounts.lock_user(id),
         {user, _} <- Accounts.get_user_by_session_token(session),
         true <- Accounts.sudo_mode?(user, -10) do
      {:ok, user}
    else
      _ -> {:error, :reauthenticate}
    end
  end

  defp recent_user(_session), do: {:error, :reauthenticate}

  defp consume_attempt(user) do
    now = now()
    started = user.second_factor_window_at

    cond do
      is_nil(started) or DateTime.diff(now, started) >= @window_seconds ->
        {:ok, update!(user, %{second_factor_attempts: 1, second_factor_window_at: now})}

      user.second_factor_attempts < @max_attempts ->
        {:ok, update!(user, %{second_factor_attempts: user.second_factor_attempts + 1})}

      true ->
        {:error, :rate_limited}
    end
  end

  defp reset_attempts, do: %{second_factor_attempts: 0, second_factor_window_at: nil}

  defp challenge_query(challenge) do
    from t in UserToken,
      where: t.token == ^hash(decode_challenge(challenge)) and t.context == @challenge_context,
      where: t.inserted_at > ago(^@challenge_minutes, "minute")
  end

  defp decode_challenge(challenge) do
    case Base.url_decode64(challenge, padding: false) do
      {:ok, raw} -> raw
      :error -> ""
    end
  end

  defp revoke_tokens(user) do
    {_count, tokens} =
      Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id, select: t)

    Enum.filter(tokens, &(&1.context == "session"))
  end

  defp update!(user, changes), do: user |> Ecto.Changeset.change(changes) |> Repo.update!()
  defp hash(value), do: :crypto.hash(:sha256, value)
  defp now, do: DateTime.utc_now(:second)

  # Failed verification commits the attempt counter.
  defp transact(fun) do
    {:ok, result} = Repo.transaction(fun)
    result
  end
end
