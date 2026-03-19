import Config

if config_env() == :dev do
  Dotenvy.source!([".env", System.get_env()])
  |> Enum.each(fn {k, v} -> System.put_env(k, v) end)

  config :music_dance_experience,
    spotify_client_id: System.get_env("SPOTIFY_CLIENT_ID") || raise("SPOTIFY_CLIENT_ID missing"),
    spotify_client_secret: System.get_env("SPOTIFY_CLIENT_SECRET") || raise("SPOTIFY_CLIENT_SECRET missing"),
    spotify_redirect_uri: System.get_env("SPOTIFY_REDIRECT_URI") || "http://localhost:4000/auth/spotify/callback",
    app_password: System.get_env("APP_PASSWORD") || "lumon"
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/music_dance_experience start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :music_dance_experience, MusicDanceExperienceWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :music_dance_experience, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :music_dance_experience, MusicDanceExperienceWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :music_dance_experience,
    spotify_client_id: System.get_env("SPOTIFY_CLIENT_ID") || raise("SPOTIFY_CLIENT_ID missing"),
    spotify_client_secret: System.get_env("SPOTIFY_CLIENT_SECRET") || raise("SPOTIFY_CLIENT_SECRET missing"),
    spotify_redirect_uri: System.get_env("SPOTIFY_REDIRECT_URI") || raise("SPOTIFY_REDIRECT_URI missing"),
    app_password: System.get_env("APP_PASSWORD") || raise("APP_PASSWORD missing")
end
