defmodule MusicDanceExperience.QueueAgent do
  use Agent

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
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:track_queued, entry})
    entry
  end

  @doc "Populate the queue from Spotify's current upcoming queue (used on reconnect/restart)."
  def seed_from_spotify do
    case MusicDanceExperience.Spotify.queued_uris_with_tracks() do
      {:ok, tracks} ->
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

      _ ->
        :ok
    end
  end

  @doc "Remove the currently playing track and anything queued before it."
  def remove_up_to_uri(uri) do
    entries = Agent.get(__MODULE__, & &1)
    idx = Enum.find_index(entries, &(&1.uri == uri))

    if idx != nil do
      to_remove = entries |> Enum.take(idx + 1) |> Enum.map(& &1.id)
      Agent.update(__MODULE__, fn e -> Enum.reject(e, &(&1.id in to_remove)) end)
      Enum.each(to_remove, &Phoenix.PubSub.broadcast(@pubsub, @topic, {:track_removed, &1}))
    end
  end

  @doc "Remove any local entries whose URIs are not in the given Spotify queue URI list, ignoring recently added tracks."
  def remove_if_not_in(spotify_uris) do
    uri_set = MapSet.new(spotify_uris)
    now = DateTime.utc_now()
    entries = Agent.get(__MODULE__, & &1)

    to_remove =
      entries
      |> Enum.reject(fn entry ->
        MapSet.member?(uri_set, entry.uri) or
          DateTime.diff(now, entry.queued_at) < 15
      end)
      |> Enum.map(& &1.id)

    if to_remove != [] do
      Agent.update(__MODULE__, fn e -> Enum.reject(e, &(&1.id in to_remove)) end)
      Enum.each(to_remove, &Phoenix.PubSub.broadcast(@pubsub, @topic, {:track_removed, &1}))
    end
  end

  @doc "Returns all queued tracks in order."
  def list, do: Agent.get(__MODULE__, & &1)

  @doc "The PubSub topic to subscribe to for real-time queue updates."
  def topic, do: @topic
end
