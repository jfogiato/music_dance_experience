defmodule MusicDanceExperience.SpotifyToken do
  use GenServer

  # State: nil | %{access_token, refresh_token, expires_at}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def init(_), do: {:ok, nil}

  @doc "Store tokens after OAuth callback."
  def set_tokens(access_token, refresh_token, expires_in) do
    GenServer.call(__MODULE__, {:set_tokens, access_token, refresh_token, expires_in})
  end

  @doc "Returns {:ok, token} or {:error, reason}. Auto-refreshes if expired."
  def get_token, do: GenServer.call(__MODULE__, :get_token)

  @doc "Returns true if tokens have been set."
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  # --- Callbacks ---

  def handle_call({:set_tokens, access, refresh, expires_in}, _from, _state) do
    state = %{
      access_token: access,
      refresh_token: refresh,
      expires_at: System.system_time(:second) + expires_in - 60
    }

    {:reply, :ok, state}
  end

  def handle_call(:get_token, _from, nil) do
    {:reply, {:error, :not_connected}, nil}
  end

  def handle_call(:get_token, _from, state) do
    if System.system_time(:second) >= state.expires_at do
      case do_refresh(state.refresh_token) do
        {:ok, new_access, new_expires_in} ->
          new_state = %{
            state
            | access_token: new_access,
              expires_at: System.system_time(:second) + new_expires_in - 60
          }

          {:reply, {:ok, new_access}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:ok, state.access_token}, state}
    end
  end

  def handle_call(:connected?, _from, nil), do: {:reply, false, nil}
  def handle_call(:connected?, _from, state), do: {:reply, true, state}

  # --- Private ---

  defp do_refresh(refresh_token) do
    client_id = Application.get_env(:music_dance_experience, :spotify_client_id)
    client_secret = Application.get_env(:music_dance_experience, :spotify_client_secret)

    resp =
      Req.post!("https://accounts.spotify.com/api/token",
        form: %{grant_type: "refresh_token", refresh_token: refresh_token},
        auth: {:basic, "#{client_id}:#{client_secret}"}
      )

    if resp.status == 200 do
      {:ok, resp.body["access_token"], resp.body["expires_in"]}
    else
      {:error, :refresh_failed}
    end
  end
end
