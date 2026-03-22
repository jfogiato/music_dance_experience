defmodule MusicDanceExperience.QueuePoller do
  use GenServer

  alias MusicDanceExperience.{Spotify, QueueAgent}

  @pubsub MusicDanceExperience.PubSub
  @topic "queue:updates"
  @poll_interval 10_000
  @sync_every 3

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def now_playing, do: GenServer.call(__MODULE__, :now_playing)

  @impl true
  def init(_) do
    schedule_poll()
    {:ok, %{now_playing: nil, tick: 0}}
  end

  @impl true
  def handle_info(:poll, %{now_playing: prev, tick: tick} = state) do
    new_state =
      case Spotify.now_playing() do
        {:ok, track} when not is_nil(track) ->
          if prev == nil or prev.uri != track.uri do
            QueueAgent.remove_up_to_uri(track.uri)
            Phoenix.PubSub.broadcast(@pubsub, @topic, {:now_playing, track})
          end
          %{state | now_playing: track}

        {:ok, nil} ->
          if prev != nil do
            Phoenix.PubSub.broadcast(@pubsub, @topic, {:now_playing, nil})
          end
          %{state | now_playing: nil}

        _ ->
          state
      end

    new_tick = tick + 1
    if rem(new_tick, @sync_every) == 0, do: QueueAgent.sync_with_spotify()

    schedule_poll()
    {:noreply, %{new_state | tick: new_tick}}
  end

  @impl true
  def handle_call(:now_playing, _from, state) do
    {:reply, state.now_playing, state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)
end
