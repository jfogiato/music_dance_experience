defmodule MusicDanceExperienceWeb.Router do
  use MusicDanceExperienceWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MusicDanceExperienceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug MusicDanceExperienceWeb.Plugs.RequireAuth
  end

  # Public routes — login + Spotify OAuth
  scope "/", MusicDanceExperienceWeb do
    pipe_through :browser

    get "/login", AuthController, :login
    post "/login", AuthController, :authenticate
    delete "/logout", AuthController, :logout
    get "/logout", AuthController, :logout

    get "/auth/spotify", AuthController, :spotify_auth
    get "/auth/spotify/callback", AuthController, :spotify_callback
  end

  # Authenticated routes
  scope "/", MusicDanceExperienceWeb do
    pipe_through [:browser, :require_auth]

    live "/", QueueLive
  end
end
