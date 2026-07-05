defmodule Metastatic.Semantic.Domains.Auth do
  @moduledoc """
  Authentication and authorization operation patterns for semantic enrichment.

  This module defines patterns for detecting auth operations across
  multiple languages and auth libraries. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Libraries

  ### Elixir
  - **Guardian** - JWT authentication
  - **Pow** - User authentication
  - **Bcrypt/Argon2** - Password hashing
  - **Ueberauth** - OAuth authentication

  ### Python
  - **Flask-Login** - Flask authentication
  - **Django auth** - Django authentication
  - **passlib** - Password hashing
  - **PyJWT/python-jose** - JWT handling

  ### Ruby
  - **Devise** - Rails authentication
  - **Warden** - Rack authentication
  - **bcrypt** - Password hashing
  - **Knock** - JWT authentication

  ### JavaScript
  - **Passport.js** - Node.js authentication
  - **jsonwebtoken** - JWT handling
  - **bcrypt** - Password hashing
  - **Auth0** - Auth0 SDK

  ## Auth Operations

  | Operation | Description |
  |-----------|-------------|
  | `:login` | User login/sign-in |
  | `:logout` | User logout/sign-out |
  | `:authenticate` | Verify user credentials |
  | `:register` | User registration |
  | `:verify_token` | JWT/token verification |
  | `:generate_token` | JWT/token generation |
  | `:refresh_token` | Token refresh |
  | `:hash_password` | Password hashing |
  | `:verify_password` | Password verification |
  | `:authorize` | Check authorization/permissions |
  | `:oauth` | OAuth flow operations |
  | `:session` | Session management |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The auth operation type
    - `:framework` - The auth library identifier
    - `:extract_target` - Strategy for extracting user/resource
  """

  alias Metastatic.Semantic.Patterns

  defmodule R do
    @moduledoc false

    # ----- Elixir/Guardian Patterns -----

    def elixir_guardian_patterns,
      do: [
        {"Guardian.encode_and_sign",
         %{operation: :generate_token, framework: :guardian, extract_target: :first_arg}},
        {"Guardian.decode_and_verify",
         %{operation: :verify_token, framework: :guardian, extract_target: :first_arg}},
        {"Guardian.resource_from_token",
         %{operation: :verify_token, framework: :guardian, extract_target: :first_arg}},
        {"Guardian.revoke",
         %{operation: :logout, framework: :guardian, extract_target: :first_arg}},
        {"Guardian.refresh",
         %{operation: :refresh_token, framework: :guardian, extract_target: :none}},
        {"Guardian.Plug.sign_in",
         %{operation: :login, framework: :guardian, extract_target: :first_arg}},
        {"Guardian.Plug.sign_out",
         %{operation: :logout, framework: :guardian, extract_target: :none}},
        {"Guardian.Plug.current_resource",
         %{operation: :authenticate, framework: :guardian, extract_target: :none}},
        {"Guardian.Plug.authenticated?",
         %{operation: :authenticate, framework: :guardian, extract_target: :none}},
        # Wildcard for custom Guardian modules
        {"*.Guardian.encode_and_sign",
         %{operation: :generate_token, framework: :guardian, extract_target: :first_arg}},
        {"*.Guardian.decode_and_verify",
         %{operation: :verify_token, framework: :guardian, extract_target: :first_arg}}
      ]

    # ----- Elixir/Pow Patterns -----

    def elixir_pow_patterns,
      do: [
        {"Pow.Plug.authenticate_user",
         %{operation: :authenticate, framework: :pow, extract_target: :none}},
        {"Pow.Plug.create_user", %{operation: :register, framework: :pow, extract_target: :none}},
        {"Pow.Plug.update_user",
         %{operation: :authenticate, framework: :pow, extract_target: :none}},
        {"Pow.Plug.delete_user", %{operation: :logout, framework: :pow, extract_target: :none}},
        {"Pow.Plug.current_user",
         %{operation: :authenticate, framework: :pow, extract_target: :none}},
        {"Pow.Operations.authenticate",
         %{operation: :authenticate, framework: :pow, extract_target: :none}},
        {"Pow.Operations.create", %{operation: :register, framework: :pow, extract_target: :none}}
      ]

    # ----- Elixir/Password Hashing Patterns -----

    def elixir_password_patterns,
      do: [
        {"Bcrypt.hash_pwd_salt",
         %{operation: :hash_password, framework: :bcrypt_elixir, extract_target: :first_arg}},
        {"Bcrypt.verify_pass",
         %{operation: :verify_password, framework: :bcrypt_elixir, extract_target: :first_arg}},
        {"Bcrypt.no_user_verify",
         %{operation: :verify_password, framework: :bcrypt_elixir, extract_target: :none}},
        {"Argon2.hash_pwd_salt",
         %{operation: :hash_password, framework: :argon2_elixir, extract_target: :first_arg}},
        {"Argon2.verify_pass",
         %{operation: :verify_password, framework: :argon2_elixir, extract_target: :first_arg}},
        {"Argon2.no_user_verify",
         %{operation: :verify_password, framework: :argon2_elixir, extract_target: :none}},
        {"Pbkdf2.hash_pwd_salt",
         %{operation: :hash_password, framework: :pbkdf2_elixir, extract_target: :first_arg}},
        {"Pbkdf2.verify_pass",
         %{operation: :verify_password, framework: :pbkdf2_elixir, extract_target: :first_arg}},
        {"Comeonin.Bcrypt.hashpwsalt",
         %{operation: :hash_password, framework: :comeonin, extract_target: :first_arg}},
        {"Comeonin.Bcrypt.checkpw",
         %{operation: :verify_password, framework: :comeonin, extract_target: :first_arg}}
      ]

    # ----- Elixir/Ueberauth Patterns -----

    def elixir_ueberauth_patterns,
      do: [
        {"Ueberauth.Strategy.Helpers.callback_url",
         %{operation: :oauth, framework: :ueberauth, extract_target: :none}},
        {"Ueberauth.run_request",
         %{operation: :oauth, framework: :ueberauth, extract_target: :none}},
        {"Ueberauth.run_callback",
         %{operation: :oauth, framework: :ueberauth, extract_target: :none}}
      ]

    # ----- Python/Flask-Login Patterns -----

    def python_flask_login_patterns,
      do: [
        {"login_user", %{operation: :login, framework: :flask_login, extract_target: :first_arg}},
        {"logout_user", %{operation: :logout, framework: :flask_login, extract_target: :none}},
        {"current_user",
         %{operation: :authenticate, framework: :flask_login, extract_target: :none}},
        {"login_required",
         %{operation: :authorize, framework: :flask_login, extract_target: :none}},
        {"fresh_login_required",
         %{operation: :authorize, framework: :flask_login, extract_target: :none}}
      ]

    # ----- Python/Django Auth Patterns -----

    def python_django_patterns,
      do: [
        {"authenticate", %{operation: :authenticate, framework: :django, extract_target: :none}},
        {"login", %{operation: :login, framework: :django, extract_target: :none}},
        {"logout", %{operation: :logout, framework: :django, extract_target: :none}},
        {"get_user", %{operation: :authenticate, framework: :django, extract_target: :none}},
        {"User.objects.create_user",
         %{operation: :register, framework: :django, extract_target: :none}},
        {"User.objects.create_superuser",
         %{operation: :register, framework: :django, extract_target: :none}},
        {"check_password",
         %{operation: :verify_password, framework: :django, extract_target: :none}},
        {"make_password",
         %{operation: :hash_password, framework: :django, extract_target: :none}},
        {"set_password", %{operation: :hash_password, framework: :django, extract_target: :none}},
        {~r/\.has_perm$/,
         %{operation: :authorize, framework: :django, extract_target: :receiver}},
        {~r/\.has_perms$/,
         %{operation: :authorize, framework: :django, extract_target: :receiver}},
        {"permission_required",
         %{operation: :authorize, framework: :django, extract_target: :first_arg}},
        {"login_required", %{operation: :authorize, framework: :django, extract_target: :none}}
      ]

    # ----- Python/JWT Patterns -----

    def python_jwt_patterns,
      do: [
        {"jwt.encode",
         %{operation: :generate_token, framework: :pyjwt, extract_target: :first_arg}},
        {"jwt.decode",
         %{operation: :verify_token, framework: :pyjwt, extract_target: :first_arg}},
        {"jose.jwt.encode",
         %{operation: :generate_token, framework: :jose, extract_target: :first_arg}},
        {"jose.jwt.decode",
         %{operation: :verify_token, framework: :jose, extract_target: :first_arg}},
        {"jose.jws.sign",
         %{operation: :generate_token, framework: :jose, extract_target: :first_arg}},
        {"jose.jws.verify",
         %{operation: :verify_token, framework: :jose, extract_target: :first_arg}}
      ]

    # ----- Python/Passlib Patterns -----

    def python_passlib_patterns,
      do: [
        {~r/\.hash$/,
         %{operation: :hash_password, framework: :passlib, extract_target: :first_arg}},
        {~r/\.verify$/,
         %{operation: :verify_password, framework: :passlib, extract_target: :first_arg}},
        {"passlib.hash.bcrypt.hash",
         %{operation: :hash_password, framework: :passlib, extract_target: :first_arg}},
        {"passlib.hash.bcrypt.verify",
         %{operation: :verify_password, framework: :passlib, extract_target: :first_arg}},
        {"passlib.hash.argon2.hash",
         %{operation: :hash_password, framework: :passlib, extract_target: :first_arg}},
        {"passlib.hash.argon2.verify",
         %{operation: :verify_password, framework: :passlib, extract_target: :first_arg}}
      ]

    # ----- Ruby/Devise Patterns -----

    def ruby_devise_patterns,
      do: [
        {"sign_in", %{operation: :login, framework: :devise, extract_target: :first_arg}},
        {"sign_out", %{operation: :logout, framework: :devise, extract_target: :first_arg}},
        {"authenticate_user!",
         %{operation: :authenticate, framework: :devise, extract_target: :none}},
        {"current_user", %{operation: :authenticate, framework: :devise, extract_target: :none}},
        {"user_signed_in?",
         %{operation: :authenticate, framework: :devise, extract_target: :none}},
        {~r/authenticate_.*!$/,
         %{operation: :authenticate, framework: :devise, extract_target: :none}},
        {~r/current_.*$/, %{operation: :authenticate, framework: :devise, extract_target: :none}},
        {~r/.*_signed_in\?$/,
         %{operation: :authenticate, framework: :devise, extract_target: :none}}
      ]

    # ----- Ruby/Warden Patterns -----

    def ruby_warden_patterns,
      do: [
        {"warden.authenticate",
         %{operation: :authenticate, framework: :warden, extract_target: :none}},
        {"warden.authenticate!",
         %{operation: :authenticate, framework: :warden, extract_target: :none}},
        {"warden.authenticated?",
         %{operation: :authenticate, framework: :warden, extract_target: :none}},
        {"warden.user", %{operation: :authenticate, framework: :warden, extract_target: :none}},
        {"warden.set_user", %{operation: :login, framework: :warden, extract_target: :first_arg}},
        {"warden.logout", %{operation: :logout, framework: :warden, extract_target: :none}}
      ]

    # ----- Ruby/bcrypt Patterns -----

    def ruby_bcrypt_patterns,
      do: [
        {"BCrypt::Password.create",
         %{operation: :hash_password, framework: :bcrypt_ruby, extract_target: :first_arg}},
        {"BCrypt::Password.new",
         %{operation: :verify_password, framework: :bcrypt_ruby, extract_target: :first_arg}},
        {~r/==/, %{operation: :verify_password, framework: :bcrypt_ruby, extract_target: :none}}
      ]

    # ----- JavaScript/Passport Patterns -----

    def javascript_passport_patterns,
      do: [
        {"passport.authenticate",
         %{operation: :authenticate, framework: :passport, extract_target: :first_arg}},
        {"passport.serializeUser",
         %{operation: :session, framework: :passport, extract_target: :none}},
        {"passport.deserializeUser",
         %{operation: :session, framework: :passport, extract_target: :none}},
        {"passport.use",
         %{operation: :authenticate, framework: :passport, extract_target: :none}},
        {"passport.initialize",
         %{operation: :session, framework: :passport, extract_target: :none}},
        {"passport.session", %{operation: :session, framework: :passport, extract_target: :none}},
        {"req.login", %{operation: :login, framework: :passport, extract_target: :first_arg}},
        {"req.logIn", %{operation: :login, framework: :passport, extract_target: :first_arg}},
        {"req.logout", %{operation: :logout, framework: :passport, extract_target: :none}},
        {"req.logOut", %{operation: :logout, framework: :passport, extract_target: :none}},
        {"req.isAuthenticated",
         %{operation: :authenticate, framework: :passport, extract_target: :none}},
        {"req.isUnauthenticated",
         %{operation: :authenticate, framework: :passport, extract_target: :none}},
        {"req.user", %{operation: :authenticate, framework: :passport, extract_target: :none}}
      ]

    # ----- JavaScript/jsonwebtoken Patterns -----

    def javascript_jwt_patterns,
      do: [
        {"jwt.sign",
         %{operation: :generate_token, framework: :jsonwebtoken, extract_target: :first_arg}},
        {"jwt.verify",
         %{operation: :verify_token, framework: :jsonwebtoken, extract_target: :first_arg}},
        {"jwt.decode",
         %{operation: :verify_token, framework: :jsonwebtoken, extract_target: :first_arg}},
        {"jsonwebtoken.sign",
         %{operation: :generate_token, framework: :jsonwebtoken, extract_target: :first_arg}},
        {"jsonwebtoken.verify",
         %{operation: :verify_token, framework: :jsonwebtoken, extract_target: :first_arg}},
        {"jsonwebtoken.decode",
         %{operation: :verify_token, framework: :jsonwebtoken, extract_target: :first_arg}}
      ]

    # ----- JavaScript/bcrypt Patterns -----

    def javascript_bcrypt_patterns,
      do: [
        {"bcrypt.hash",
         %{operation: :hash_password, framework: :bcryptjs, extract_target: :first_arg}},
        {"bcrypt.hashSync",
         %{operation: :hash_password, framework: :bcryptjs, extract_target: :first_arg}},
        {"bcrypt.compare",
         %{operation: :verify_password, framework: :bcryptjs, extract_target: :first_arg}},
        {"bcrypt.compareSync",
         %{operation: :verify_password, framework: :bcryptjs, extract_target: :first_arg}},
        {"bcrypt.genSalt",
         %{operation: :hash_password, framework: :bcryptjs, extract_target: :none}},
        {"bcrypt.genSaltSync",
         %{operation: :hash_password, framework: :bcryptjs, extract_target: :none}}
      ]

    # ----- JavaScript/Auth0 Patterns -----

    def javascript_auth0_patterns,
      do: [
        {"auth0.getAccessTokenSilently",
         %{operation: :refresh_token, framework: :auth0, extract_target: :none}},
        {"auth0.loginWithRedirect",
         %{operation: :login, framework: :auth0, extract_target: :none}},
        {"auth0.loginWithPopup", %{operation: :login, framework: :auth0, extract_target: :none}},
        {"auth0.logout", %{operation: :logout, framework: :auth0, extract_target: :none}},
        {"auth0.isAuthenticated",
         %{operation: :authenticate, framework: :auth0, extract_target: :none}},
        {"auth0.getUser", %{operation: :authenticate, framework: :auth0, extract_target: :none}},
        {"auth0.handleRedirectCallback",
         %{operation: :oauth, framework: :auth0, extract_target: :none}}
      ]
  end

  # ----- Registration -----

  @doc """
  Registers all auth patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (Guardian + Pow + Password hashing + Ueberauth)
    Patterns.register(
      :auth,
      :elixir,
      R.elixir_guardian_patterns() ++
        R.elixir_pow_patterns() ++ R.elixir_password_patterns() ++ R.elixir_ueberauth_patterns()
    )

    # Python patterns (Flask-Login + Django + JWT + Passlib)
    Patterns.register(
      :auth,
      :python,
      R.python_flask_login_patterns() ++
        R.python_django_patterns() ++ R.python_jwt_patterns() ++ R.python_passlib_patterns()
    )

    # Ruby patterns (Devise + Warden + bcrypt)
    Patterns.register(
      :auth,
      :ruby,
      R.ruby_devise_patterns() ++ R.ruby_warden_patterns() ++ R.ruby_bcrypt_patterns()
    )

    # JavaScript patterns (Passport + JWT + bcrypt + Auth0)
    Patterns.register(
      :auth,
      :javascript,
      R.javascript_passport_patterns() ++
        R.javascript_jwt_patterns() ++
        R.javascript_bcrypt_patterns() ++ R.javascript_auth0_patterns()
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.Auth.register_all()
