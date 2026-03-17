defmodule MusicDanceExperienceWeb.AuthController do
  use MusicDanceExperienceWeb, :controller

  alias MusicDanceExperience.{Spotify, SpotifyToken, UsernameGenerator}

  def login(conn, _params) do
    suggested = UsernameGenerator.generate()
    render(conn, :login, suggested_username: suggested)
  end

  def authenticate(conn, %{"username" => username, "access_code" => code}) do
    app_password = Application.get_env(:music_dance_experience, :app_password)
    username = String.trim(username)

    cond do
      username == "" ->
        conn
        |> put_flash(:error, "DESIGNATION REQUIRED. PLEASE PROVIDE AN EMPLOYEE NAME.")
        |> render(:login, suggested_username: UsernameGenerator.generate())

      code != app_password ->
        conn
        |> put_flash(:error, "INVALID ACCESS CODE. REPORT TO YOUR WELLNESS COUNSELOR.")
        |> render(:login, suggested_username: UsernameGenerator.generate())

      true ->
        conn
        |> put_session(:authenticated, true)
        |> put_session(:username, username)
        |> redirect(to: "/")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end

  # --- Spotify OAuth ---

  def spotify_auth(conn, _params) do
    redirect(conn, external: Spotify.auth_url())
  end

  def spotify_callback(conn, %{"code" => code}) do
    case Spotify.exchange_code(code) do
      {:ok, access, refresh, expires_in} ->
        SpotifyToken.set_tokens(access, refresh, expires_in)
        MusicDanceExperience.QueueAgent.seed_from_spotify()

        conn
        |> put_flash(:info, "SPOTIFY INTEGRATION CONFIRMED. LUMON APPROVES OF YOUR COMPLIANCE.")
        |> redirect(to: "/")

      {:error, _} ->
        conn
        |> put_flash(:error, "SPOTIFY INTEGRATION FAILED. PLEASE CONSULT YOUR HANDLER.")
        |> redirect(to: "/")
    end
  end

  def spotify_callback(conn, %{"error" => _}) do
    conn
    |> put_flash(:error, "SPOTIFY AUTHORIZATION DENIED. THIS HAS BEEN NOTED.")
    |> redirect(to: "/")
  end
end
