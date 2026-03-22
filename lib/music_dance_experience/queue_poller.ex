defmodule MusicDanceExperience.QueuePoller do
  use GenServer
  require Logger

  alias MusicDanceExperience.{Spotify, QueueAgent}

  @pubsub MusicDanceExperience.PubSub
  @topic "queue:updates"
  @presence_topic "queue:presence"
  @poll_interval 10_000
  @sync_every 3

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def now_playing, do: GenServer.call(__MODULE__, :now_playing)

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(@pubsub, @presence_topic)
    Logger.info("[QueuePoller] Started, subscribed to presence topic #{@presence_topic}")
    schedule_poll()
    {:ok, %{now_playing: nil, tick: 0, users_online: 0}}
  end

  @impl true
  def handle_info(:poll, %{now_playing: prev, tick: tick, users_online: count} = state) do
    Logger.debug("[QueuePoller] Polling — #{count} user(s) online, tick=#{tick}")

    new_state =
      case Spotify.now_playing() do
        {:ok, track} when not is_nil(track) ->
          Logger.info(
            "[QueuePoller] Playback device — track=#{track.name} uri=#{track.uri} is_playing=#{inspect(track.is_playing)} progress_ms=#{inspect(track.progress_ms)} device=#{inspect(track.device)}"
          )

          if prev == nil or prev.uri != track.uri do
            Logger.info("[QueuePoller] Track changed: #{track.name} by #{track.artist} (#{track.uri})")
            QueueAgent.remove_up_to_uri(track.uri)
            Phoenix.PubSub.broadcast(@pubsub, @topic, {:now_playing, track})
          else
            Logger.debug("[QueuePoller] Track unchanged: #{track.name} (#{track.uri})")
          end

          %{state | now_playing: track}

        {:ok, nil} ->
          if prev != nil do
            Logger.info("[QueuePoller] Playback stopped")
            Phoenix.PubSub.broadcast(@pubsub, @topic, {:now_playing, nil})
          end
          %{state | now_playing: nil}

        {:error, reason} ->
          Logger.warning("[QueuePoller] now_playing failed: #{inspect(reason)}")
          state
      end

    new_tick = tick + 1

    if rem(new_tick, @sync_every) == 0 do
      Logger.debug("[QueuePoller] Running queue sync (tick=#{new_tick})")
      QueueAgent.sync_with_spotify()
    end

    schedule_poll()
    {:noreply, %{new_state | tick: new_tick}}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}, state) do
    usernames =
      MusicDanceExperienceWeb.Presence.list(@presence_topic)
      |> Map.keys()
      |> Enum.sort()

    users_online = length(usernames)

    Logger.info(
      "[QueuePoller] Presence diff — joins=#{map_size(payload.joins)}, leaves=#{map_size(payload.leaves)}, total=#{users_online}, users=#{inspect(usernames)}"
    )

    {:noreply, %{state | users_online: users_online}}
  end

  @impl true
  def handle_call(:now_playing, _from, state) do
    {:reply, state.now_playing, state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)
end
