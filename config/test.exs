import Config

config :music_dance_experience, MusicDanceExperienceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pJM9ptf0GqBbHLXYCIzhHKP0t4Wyk2i+prWQs+R6m9SsYx10E/OdgW0F6eIUYlMS",
  server: false

config :music_dance_experience,
  spotify_client_id: "test_client_id",
  spotify_client_secret: "test_client_secret",
  spotify_redirect_uri: "http://localhost:4002/auth/spotify/callback",
  app_password: "test"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
