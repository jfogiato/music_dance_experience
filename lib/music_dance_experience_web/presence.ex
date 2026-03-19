defmodule MusicDanceExperienceWeb.Presence do
  use Phoenix.Presence,
    otp_app: :music_dance_experience,
    pubsub_server: MusicDanceExperience.PubSub
end
