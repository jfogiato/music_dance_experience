defmodule MusicDanceExperience.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MusicDanceExperienceWeb.Telemetry,
      MusicDanceExperience.Repo,
      {DNSCluster, query: Application.get_env(:music_dance_experience, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MusicDanceExperience.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: MusicDanceExperience.Finch},
      # Start a worker by calling: MusicDanceExperience.Worker.start_link(arg)
      # {MusicDanceExperience.Worker, arg},
      # Start to serve requests, typically the last entry
      MusicDanceExperienceWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MusicDanceExperience.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MusicDanceExperienceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
