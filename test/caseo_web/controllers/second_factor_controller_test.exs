defmodule CaseoWeb.SecondFactorControllerTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Ecto.Query
  alias Caseo.{Accounts, Repo}
  alias Caseo.Accounts.{SecondFactor, TOTP, UserToken}

  setup %{conn: conn} do
    user = user_fixture()
    %{user: user, signed_in: log_in_user(conn, user)}
  end

  test "requires a valid authenticator code to activate and shows recovery codes once", %{
    signed_in: signed_in,
    user: user
  } do
    {conn, ticket, secret} = setup_form(signed_in)

    [uri] =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-totp-uri]:has(#totp-qr-code)")
      |> LazyHTML.attribute("data-totp-uri")

    assert %URI{scheme: "otpauth", host: "totp", path: path, query: query} = URI.parse(uri)
    assert URI.decode(path) == "/Caseo:#{user.email}"
    assert URI.decode_query(query) == %{"issuer" => "Caseo", "secret" => Base.encode32(secret)}

    invalid =
      post(conn, ~p"/users/settings/second-factor", %{
        "setup_ticket" => ticket,
        "factor_code" => "invalid"
      })

    assert redirected_to(invalid) == ~p"/users/settings/second-factor"
    refute SecondFactor.enabled?(Accounts.get_user!(user.id))

    {activated, _secret, _step, codes} = activate(signed_in)
    assert length(codes) == 10
    assert length(Enum.uniq(codes)) == 10
    assert get_resp_header(activated, "cache-control") == ["no-store"]
    refute get_session(activated, :user_token)
    assert SecondFactor.enabled?(Accounts.get_user!(user.id))
    refute Accounts.get_user_by_session_token(get_session(signed_in, :user_token))
  end

  test "email alone cannot authenticate or set a remember-me cookie when TOTP is active", %{
    signed_in: signed_in,
    user: user
  } do
    {_activated, secret, activation_step, [unused_recovery_code | _]} = activate(signed_in)
    {token, _hash} = generate_user_magic_link_token(user)

    pending =
      post(build_conn(), ~p"/users/log-in", %{
        "user" => %{"token" => token, "remember_me" => "true"}
      })

    assert redirected_to(pending) == ~p"/users/second-factor"
    refute get_session(pending, :user_token)
    refute pending.resp_cookies["_caseo_web_user_remember_me"][:value]

    assert pending |> recycle() |> get(~p"/users/settings") |> redirected_to() ==
             ~p"/users/log-in"

    replayed_link = post(build_conn(), ~p"/users/log-in", %{"user" => %{"token" => token}})
    assert redirected_to(replayed_link) == ~p"/users/log-in"

    assert pending
           |> recycle()
           |> get(~p"/users/second-factor")
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.query("#second-factor-challenge")
           |> Enum.count() == 1

    reused = submit_code(pending, TOTP.code(secret, activation_step))
    assert redirected_to(reused) == ~p"/users/second-factor"
    refute get_session(reused, :user_token)

    verified = submit_code(reused, TOTP.code(secret, activation_step + 1))
    assert redirected_to(verified) == ~p"/"
    assert get_session(verified, :user_token)
    assert verified.resp_cookies["_caseo_web_user_remember_me"][:value]

    replayed = submit_code(pending, unused_recovery_code)
    assert redirected_to(replayed) == ~p"/users/log-in"
  end

  test "consumes a recovery code once and permits disabling from the recovered session", %{
    signed_in: signed_in,
    user: user
  } do
    {_activated, _secret, _step, [code | _other_codes]} = activate(signed_in)
    pending = start_email_login(user)
    recovered = submit_code(pending, String.downcase(code))
    assert get_session(recovered, :user_token)
    assert SecondFactor.enabled?(Accounts.get_user!(user.id))

    another_pending = start_email_login(user)
    replayed = submit_code(another_pending, code)
    assert redirected_to(replayed) == ~p"/users/second-factor"
    refute get_session(replayed, :user_token)

    disabled = recovered |> recycle() |> delete(~p"/users/settings/second-factor")
    assert redirected_to(disabled) == ~p"/users/log-in"
    refute get_session(disabled, :user_token)
    user = Accounts.get_user!(user.id)
    refute SecondFactor.enabled?(user)
    assert user.recovery_code_hashes == []
    assert another_pending |> submit_code(code) |> redirected_to() == ~p"/users/log-in"
    assert user |> start_email_login() |> get_session(:user_token)
  end

  test "password login also requires the factor and attempts are shared across challenges", %{
    user: user
  } do
    user = set_password(user)
    signed_in = log_in_user(build_conn(), user)
    {_activated, _secret, _step, [recovery_code | _]} = activate(signed_in)

    pending =
      post(build_conn(), ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(pending) == ~p"/users/second-factor"
    refute get_session(pending, :user_token)

    Enum.reduce(1..5, pending, fn _, conn -> submit_code(conn, "invalid") end)

    limited = user |> start_email_login() |> submit_code(recovery_code)
    refute get_session(limited, :user_token)
    assert Phoenix.Flash.get(limited.assigns.flash, :error) =~ "Too many attempts"
  end

  test "expired challenges never grant a session", %{signed_in: signed_in, user: user} do
    {_activated, _secret, _step, [code | _]} = activate(signed_in)
    pending = start_email_login(user)
    expiry = DateTime.add(DateTime.utc_now(:second), -6, :minute)

    Repo.update_all(
      from(t in UserToken, where: t.user_id == ^user.id and t.context == "second_factor"),
      set: [inserted_at: expiry]
    )

    expired = submit_code(pending, code)
    assert redirected_to(expired) == ~p"/users/log-in"
    refute get_session(expired, :user_token)
  end

  test "disabling requires recent authentication", %{signed_in: signed_in, user: user} do
    {_activated, _secret, _step, [code | _]} = activate(signed_in)
    verified = user |> start_email_login() |> submit_code(code)
    session = get_session(verified, :user_token)

    Repo.update_all(
      from(t in UserToken, where: t.token == ^session),
      set: [authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)]
    )

    stale = verified |> recycle() |> delete(~p"/users/settings/second-factor")
    assert redirected_to(stale) == ~p"/users/log-in"
    assert SecondFactor.enabled?(Accounts.get_user!(user.id))
  end

  test "only a passkey verified with user verification satisfies the policy", %{
    signed_in: signed_in,
    user: user
  } do
    activate(signed_in)
    user = Accounts.get_user!(user.id)

    assert SecondFactor.required?(user, :magic_link)
    assert SecondFactor.required?(user, :password)
    assert SecondFactor.required?(user, :passkey)
    refute SecondFactor.required?(user, :user_verified_passkey)
  end

  defp setup_form(conn) do
    conn = get(conn, ~p"/users/settings/second-factor")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    [ticket] =
      document
      |> LazyHTML.query("#enable-totp input[name=setup_ticket]")
      |> LazyHTML.attribute("value")

    secret =
      document
      |> LazyHTML.query("#totp-setup-key")
      |> LazyHTML.text()
      |> String.trim()
      |> Base.decode32!()

    {conn, ticket, secret}
  end

  defp activate(conn) do
    {conn, ticket, secret} = setup_form(conn)
    step = div(System.os_time(:second), 30)

    conn =
      post(conn, ~p"/users/settings/second-factor", %{
        "setup_ticket" => ticket,
        "factor_code" => TOTP.code(secret, step)
      })

    codes =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#recovery-codes li")
      |> Enum.map(&LazyHTML.text/1)

    {conn, secret, step, codes}
  end

  defp start_email_login(user) do
    {token, _hash} = generate_user_magic_link_token(user)
    post(build_conn(), ~p"/users/log-in", %{"user" => %{"token" => token}})
  end

  defp submit_code(conn, code) do
    conn |> recycle() |> post(~p"/users/second-factor", %{"factor_code" => code})
  end
end
