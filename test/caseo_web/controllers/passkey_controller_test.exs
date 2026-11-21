defmodule CaseoWeb.PasskeyControllerTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Ecto.Query
  alias Caseo.{Accounts, Repo}
  alias Caseo.Accounts.{Passkeys, UserToken}

  @register "/users/settings/passkeys"
  @login "/users/log-in/passkey"
  @origin "http://localhost:4000"
  @rp "localhost"

  test "registers, renames, signs in with TOTP enabled, and revokes a passkey", %{conn: conn} do
    user = user_fixture()
    user = user |> Ecto.Changeset.change(totp_secret: "configured") |> Repo.update!()
    {signed_in, key} = enroll(conn, user)

    assert [passkey] = Passkeys.list(user)
    assert passkey.name == "Laptop"
    document = signed_in |> get(@register) |> html_response(200) |> LazyHTML.from_document()
    assert Enum.count(LazyHTML.query(document, "#add-passkey #new-passkey-name")) == 1
    assert Enum.count(LazyHTML.query(document, "#rename-passkey-#{passkey.id}")) == 1

    updated = patch(signed_in, "#{@register}/#{passkey.id}", %{"name" => "Work laptop"})
    assert redirected_to(updated) == @register
    assert [%{name: "Work laptop"}] = Passkeys.list(user)

    {attempt, response} = login_attempt(build_conn(), key)
    logged_in = post(recycle(attempt), @login, response)
    assert redirected_to(logged_in) == ~p"/"

    assert {authenticated, _} =
             Accounts.get_user_by_session_token(get_session(logged_in, :user_token))

    assert authenticated.id == user.id
    refute get_session(logged_in, :second_factor_challenge)

    assert_error(post(recycle(attempt), @login, response))
    revoked = delete(recycle(updated), "#{@register}/#{passkey.id}")
    assert redirected_to(revoked) == @register
    assert Passkeys.list(user) == []

    {attempt, response} = login_attempt(build_conn(), key)
    assert_error(post(recycle(attempt), @login, response))
  end

  test "rejects wrong origin, RP ID, user handle, and missing user verification", %{conn: conn} do
    {_signed_in, key} = enroll(conn, user_fixture())

    for attrs <- [
          [origin: "https://different.example"],
          [rp: "different.example"],
          [flags: 0x01],
          [handle: encode(:crypto.strong_rand_bytes(16))]
        ] do
      {attempt, response} = login_attempt(build_conn(), key, attrs)
      assert_error(post(recycle(attempt), @login, response))
    end
  end

  test "binds challenges to the browser session, consumes failed attempts, and rejects expiration",
       %{
         conn: conn
       } do
    {_signed_in, key} = enroll(conn, user_fixture())
    {attempt, response} = login_attempt(build_conn(), key)
    assert_error(post(build_conn(), @login, response))

    assert_error(
      post(recycle(attempt), @login, Map.put(response, "signature", encode("invalid")))
    )

    assert_error(post(recycle(attempt), @login, response))

    {attempt, response} = login_attempt(build_conn(), key)
    expired = DateTime.add(DateTime.utc_now(:second), -1)
    Repo.update_all(from(c in "passkey_challenges"), set: [expires_at: expired])
    assert_error(post(recycle(attempt), @login, response))
  end

  test "management is scoped to the owner and enrollment rechecks recent authentication", %{
    conn: conn
  } do
    user = user_fixture()
    {_signed_in, _key} = enroll(conn, user)
    [passkey] = Passkeys.list(user)

    other = log_in_user(build_conn(), user_fixture())

    assert redirected_to(patch(other, "#{@register}/#{passkey.id}", %{"name" => "Other"})) ==
             @register

    assert redirected_to(delete(other, "#{@register}/#{passkey.id}")) == @register
    assert [%{name: "Laptop"}] = Passkeys.list(user)

    options = post(log_in_user(build_conn(), user), "#{@register}/options")
    challenge = json_response(options, 200)["challenge"]
    token = get_session(options, :user_token)
    stale = DateTime.add(DateTime.utc_now(:second), -11, :minute)

    Repo.update_all(from(t in UserToken, where: t.token == ^token),
      set: [authenticated_at: stale]
    )

    result = post(recycle(options), @register, %{"challenge" => challenge})
    assert json_response(result, 200)["location"] == ~p"/users/log-in"

    assert redirected_to(delete(recycle(options), "#{@register}/#{passkey.id}")) ==
             ~p"/users/log-in"
  end

  defp enroll(conn, user) do
    options = post(log_in_user(conn, user), "#{@register}/options")
    %{"challenge" => challenge, "user" => %{"id" => handle}} = json_response(options, 200)

    {<<4, x::binary-size(32), y::binary-size(32)>>, private} =
      :crypto.generate_key(:ecdh, :secp256r1)

    credential_id = :crypto.strong_rand_bytes(32)
    key = CBOR.encode(%{1 => 2, 3 => -7, -1 => 1, -2 => cbor_bytes(x), -3 => cbor_bytes(y)})
    auth_data = rp_hash(@rp) <> <<0x45, 0::32, 0::128, 32::16>> <> credential_id <> key

    attestation =
      CBOR.encode(%{"fmt" => "none", "authData" => cbor_bytes(auth_data), "attStmt" => %{}})

    params = %{
      "name" => "Laptop",
      "challenge" => challenge,
      "credentialId" => encode(credential_id),
      "clientDataJSON" => encode(client_data("webauthn.create", challenge, @origin)),
      "attestationObject" => encode(attestation)
    }

    registered = post(recycle(options), @register, params)
    assert json_response(registered, 200)["location"] == @register
    {registered, %{private: private, credential_id: credential_id, handle: handle}}
  end

  defp login_attempt(conn, key, attrs \\ []) do
    conn = post(conn, "#{@login}/options")
    %{"challenge" => challenge} = json_response(conn, 200)
    data = client_data("webauthn.get", challenge, Keyword.get(attrs, :origin, @origin))
    flags = Keyword.get(attrs, :flags, 0x05)
    auth_data = rp_hash(Keyword.get(attrs, :rp, @rp)) <> <<flags, 0::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, data), [
        key.private,
        :secp256r1
      ])

    {conn,
     %{
       "challenge" => challenge,
       "credentialId" => encode(key.credential_id),
       "clientDataJSON" => encode(data),
       "authenticatorData" => encode(auth_data),
       "signature" => encode(signature),
       "userHandle" => Keyword.get(attrs, :handle, key.handle)
     }}
  end

  defp assert_error(conn) do
    assert %{"error" => _} = json_response(conn, 422)
    refute get_session(conn, :user_token)
  end

  defp client_data(type, challenge, origin) do
    Jason.encode!(%{type: type, challenge: challenge, origin: origin, crossOrigin: false})
  end

  defp cbor_bytes(value), do: %CBOR.Tag{tag: :bytes, value: value}
  defp rp_hash(rp), do: :crypto.hash(:sha256, rp)
  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)
end
