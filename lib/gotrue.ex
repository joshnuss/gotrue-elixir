defmodule GoTrue do
  @moduledoc """
  Elixir wrapper for the [GoTrue authentication service](https://github.com/supabase/gotrue).
  """

  import Tesla, only: [get: 2, post: 3, put: 3]

  @base_url Application.get_env(:gotrue, :base_url, "http://0.0.0.0:9999")
  @access_token Application.get_env(:gotrue, :access_token)

  @doc "Get environment settings for the server"
  @spec settings() :: map
  def settings do
    client()
    |> get("/settings")
    |> handle_response(200, fn %{body: json} -> json end)
  end

  @doc "Sign up a new user with email and password"
  @spec sign_up(%{
          required(:email) => String.t(),
          required(:password) => String.t(),
          data: map(),
          audience: String.t(),
          provider: String.t()
        }) :: map
  def sign_up(credentials) do
    payload =
      credentials
      |> Map.take([:email, :password, :data, :provider])
      |> Map.merge(%{aud: credentials[:audience]})

    client()
    |> post("/signup", payload)
    |> handle_response(200, fn %{body: json} -> {:ok, json} end)
  end

  @doc "Send a password recovery email"
  @spec recover(String.t()) :: :ok | {:error, map}
  def recover(email) do
    client()
    |> post("/recover", %{email: email})
    |> handle_response()
  end

  @doc "Invite a new user to join"
  @spec invite(%{
          required(:email) => String.t(),
          data: map()
        }) :: map
  def invite(invitation) do
    client()
    |> post("/invite", invitation)
    |> handle_response(200, &user_handler/1)
  end

  @doc "Send a magic link (passwordless login)"
  @spec send_magic_link(String.t()) :: :ok | {:error, map}
  def send_magic_link(email) do
    client()
    |> post("/magiclink", %{email: email})
    |> handle_response()
  end

  @doc "Generate a URL for authorizing with an OAUTH2 provider"
  @spec url_for_provider(String.t()) :: String.t()
  def url_for_provider(provider) do
    @base_url
    |> URI.merge("authorize?provider=#{provider}")
    |> URI.to_string()
  end

  @doc "Refresh access token using a valid refresh token"
  @spec refresh_access_token(String.t()) :: {:ok, map()} | {:error, map}
  def refresh_access_token(refresh_token) do
    grant_token(:refresh_token, %{refresh_token: refresh_token})
  end

  @doc "Sign in with email and password"
  @spec sign_in(%{required(:email) => String.t(), required(:password) => String.t()}) ::
          {:ok, map()} | {:error, map}
  def sign_in(credentials) do
    grant_token(:password, credentials)
  end

  defp grant_token(type, payload) do
    client()
    |> post("/token?grant_type=#{type}", payload)
    |> handle_response(200, fn %{body: json} -> {:ok, json} end)
  end

  @doc "Sign out user using a valid JWT"
  @spec sign_out(String.t()) :: :ok | {:error, map}
  def sign_out(jwt) do
    jwt
    |> client()
    |> post("/logout", %{})
    |> handle_response(204)
  end

  @doc "Get user info using a valid JWT"
  @spec get_user(String.t()) :: {:ok, map} | {:error, map}
  def get_user(jwt) do
    jwt
    |> client()
    |> get("/user")
    |> handle_response(200, &user_handler/1)
  end

  @doc "Update user info using a valid JWT"
  @spec update_user(String.t(), map()) :: {:ok, map} | {:error, map}
  def update_user(jwt, info) do
    jwt
    |> client()
    |> put("/user", info)
    |> handle_response(200, &user_handler/1)
  end

  defp client(access_token \\ @access_token) do
    middlewares = [
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, authorization: "Bearer #{access_token}"}
    ]

    Tesla.client(middlewares)
  end

  defp parse_user(user) do
    user
  end

  defp format_error(%{status: status, body: json}) do
    %{code: status, message: json["msg"]}
  end

  defp default_handler(_response) do
    :ok
  end

  defp user_handler(%{body: json}) do
    {:ok, parse_user(json)}
  end

  defp handle_response({tag, response}, success \\ 200, fun \\ &default_handler/1) do
    case {tag, response} do
      {:ok, %{status: ^success}} ->
        fun.(response)

      {:ok, response} ->
        {:error, format_error(response)}
    end
  end
end
