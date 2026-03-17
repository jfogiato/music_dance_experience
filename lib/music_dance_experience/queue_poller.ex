defmodule MusicDanceExperience.QueuePoller do
  use GenServer

  alias MusicDanceExperience.{Spotify, QueueAgent}

  @pubsub MusicDanceExperience.PubSub
  @topic "queue:updates"
  @poll_interval 5_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def now_playing, do: GenServer.call(__MODULE__, :now_playing)

  @impl true
  def init(_) do
    schedule_poll()
    {:ok, %{now_playing: nil}}
  end

  @impl true
  def handle_info(:poll, %{now_playing: prev} = state) do
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

    case Spotify.queued_uris() do
      {:ok, uris} -> QueueAgent.remove_if_not_in(uris)
      _ -> :ok
    end

    schedule_poll()
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:now_playing, _from, state) do
    {:reply, state.now_playing, state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)
end
