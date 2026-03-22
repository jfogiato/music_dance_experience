defmodule MusicDanceExperience.QueueAgent do
  use Agent
  require Logger

  @pubsub MusicDanceExperience.PubSub
  @topic "queue:updates"

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  @doc "Add a track to the queue and broadcast the update."
  def add_track(%{name: _, artist: _, uri: _, album_art: _} = track, username) do
    entry = %{
      id: System.unique_integer([:positive, :monotonic]),
      track_name: track.name,
      artist: track.artist,
      album_art: track.album_art,
      uri: track.uri,
      username: username,
      queued_at: DateTime.utc_now()
    }

    Agent.update(__MODULE__, fn entries -> entries ++ [entry] end)
    Logger.info("[QueueAgent] Track queued by #{inspect(username)}: #{track.name} (#{track.uri})")
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:track_queued, entry})
    entry
  end

  @doc "Populate the queue from Spotify's current upcoming queue (used on reconnect/restart)."
  def seed_from_spotify do
    case MusicDanceExperience.Spotify.queued_uris_with_tracks() do
      {:ok, tracks} ->
        Logger.info("[QueueAgent] Seeding queue from Spotify with #{length(tracks)} track(s)")

        entries =
          Enum.map(tracks, fn track ->
            %{
              id: System.unique_integer([:positive, :monotonic]),
              track_name: track.name,
              artist: track.artist,
              album_art: track.album_art,
              uri: track.uri,
              username: "—",
              queued_at: DateTime.utc_now()
            }
          end)

        Agent.update(__MODULE__, fn _ -> entries end)
        Phoenix.PubSub.broadcast(@pubsub, @topic, :queue_reset)

      {:error, reason} ->
        Logger.warning("[QueueAgent] Seed from Spotify skipped: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Remove the currently playing track and anything queued before it."
  def remove_up_to_uri(uri) do
    entries = Agent.get(__MODULE__, & &1)
    idx = Enum.find_index(entries, &(&1.uri == uri))

    if idx != nil do
      to_remove = entries |> Enum.take(idx + 1) |> Enum.map(& &1.id)
      removed_uris = entries |> Enum.take(idx + 1) |> Enum.map(& &1.uri)

      Logger.info(
        "[QueueAgent] Removing #{length(to_remove)} queued track(s) up to current URI #{uri}: #{inspect(removed_uris)}"
      )

      Agent.update(__MODULE__, fn e -> Enum.reject(e, &(&1.id in to_remove)) end)
      Enum.each(to_remove, &Phoenix.PubSub.broadcast(@pubsub, @topic, {:track_removed, &1}))
    else
      Logger.debug("[QueueAgent] Current Spotify track #{uri} not found in local queue")
    end
  end

  @doc """
  Syncs the local queue to match Spotify's current queue. Preserves usernames
  for tracks already known to MDE, and adds externally-queued tracks with \"—\".
  """
  def sync_with_spotify do
    case MusicDanceExperience.Spotify.queued_uris_with_tracks() do
      {:ok, spotify_tracks} ->
        current_entries = Agent.get(__MODULE__, & &1)
        current_by_uri = Map.new(current_entries, &{&1.uri, &1})

        Logger.debug(
          "[QueueAgent] Syncing queue with Spotify: local=#{length(current_entries)} spotify=#{length(spotify_tracks)}"
        )

        synced =
          Enum.map(spotify_tracks, fn track ->
            case Map.get(current_by_uri, track.uri) do
              nil ->
                %{
                  id: System.unique_integer([:positive, :monotonic]),
                  track_name: track.name,
                  artist: track.artist,
                  album_art: track.album_art,
                  uri: track.uri,
                  username: "—",
                  queued_at: DateTime.utc_now()
                }

              existing ->
                existing
            end
          end)

        if synced != current_entries do
          Logger.info(
            "[QueueAgent] Queue sync applied: local_uris=#{inspect(Enum.map(current_entries, & &1.uri))} spotify_uris=#{inspect(Enum.map(spotify_tracks, & &1.uri))}"
          )

          Agent.update(__MODULE__, fn _ -> synced end)
          Phoenix.PubSub.broadcast(@pubsub, @topic, :queue_reset)
        else
          Logger.debug("[QueueAgent] Queue sync found no changes")
        end

      {:error, reason} ->
        Logger.warning("[QueueAgent] Queue sync skipped: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Returns all queued tracks in order."
  def list, do: Agent.get(__MODULE__, & &1)

  @doc "The PubSub topic to subscribe to for real-time queue updates."
  def topic, do: @topic
end
