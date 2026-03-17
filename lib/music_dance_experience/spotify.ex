defmodule MusicDanceExperience.Spotify do
  alias MusicDanceExperience.SpotifyToken

  @auth_base "https://accounts.spotify.com"
  @api_base "https://api.spotify.com/v1"

  @doc "Redirect URL for the host to authorize their Spotify account."
  def auth_url do
    client_id = Application.get_env(:music_dance_experience, :spotify_client_id)
    redirect_uri = Application.get_env(:music_dance_experience, :spotify_redirect_uri)

    params =
      URI.encode_query(%{
        client_id: client_id,
        response_type: "code",
        redirect_uri: redirect_uri,
        scope: "user-modify-playback-state user-read-playback-state"
      })

    "#{@auth_base}/authorize?#{params}"
  end

  @doc "Exchange authorization code for access + refresh tokens."
  def exchange_code(code) do
    client_id = Application.get_env(:music_dance_experience, :spotify_client_id)
    client_secret = Application.get_env(:music_dance_experience, :spotify_client_secret)
    redirect_uri = Application.get_env(:music_dance_experience, :spotify_redirect_uri)

    resp =
      Req.post!("#{@auth_base}/api/token",
        form: %{
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri
        },
        auth: {:basic, "#{client_id}:#{client_secret}"}
      )

    if resp.status == 200 do
      {:ok, resp.body["access_token"], resp.body["refresh_token"], resp.body["expires_in"]}
    else
      {:error, resp.body}
    end
  end

  @doc "Search for tracks. Returns {:ok, [track]} or {:error, reason}."
  def search(query) do
    with {:ok, token} <- SpotifyToken.get_token() do
      resp =
        Req.get!("#{@api_base}/search",
          params: [q: query, type: "track", limit: 8],
          headers: [authorization: "Bearer #{token}"]
        )

      if resp.status == 200 do
        tracks = resp.body["tracks"]["items"] |> Enum.map(&format_track/1)
        {:ok, tracks}
      else
        {:error, :search_failed}
      end
    end
  end

  @doc "Add a track URI to the active player queue. Returns :ok or {:error, reason}."
  def queue_track(uri) do
    with {:ok, token} <- SpotifyToken.get_token() do
      resp =
        Req.post!("#{@api_base}/me/player/queue",
          params: [uri: uri],
          headers: [authorization: "Bearer #{token}"],
          body: ""
        )

      cond do
        resp.status in 200..204 -> :ok
        resp.status == 404 -> {:error, :no_active_device}
        true -> {:error, :queue_failed}
      end
    end
  end

  @doc "Returns the list of URIs currently in Spotify's upcoming queue."
  def queued_uris do
    with {:ok, tracks} <- queued_uris_with_tracks() do
      {:ok, Enum.map(tracks, & &1.uri)}
    end
  end

  @doc "Returns the list of formatted track maps in Spotify's upcoming queue."
  def queued_uris_with_tracks do
    with {:ok, token} <- SpotifyToken.get_token() do
      resp = Req.get!("#{@api_base}/me/player/queue",
        headers: [authorization: "Bearer #{token}"]
      )

      if resp.status == 200 do
        tracks = resp.body["queue"] |> Enum.map(&format_track/1)
        {:ok, tracks}
      else
        {:error, :unavailable}
      end
    end
  end

  @doc "Returns the currently playing track map, or nil if nothing is playing."
  def now_playing do
    with {:ok, token} <- SpotifyToken.get_token() do
      resp = Req.get!("#{@api_base}/me/player/currently-playing",
        headers: [authorization: "Bearer #{token}"]
      )

      cond do
        resp.status == 200 && resp.body["item"] ->
          {:ok, format_track(resp.body["item"])}
        resp.status == 204 ->
          {:ok, nil}
        true ->
          {:error, :unavailable}
      end
    end
  end

  # --- Private ---

  defp format_track(track) do
    %{
      id: track["id"],
      name: track["name"],
      artist: track["artists"] |> Enum.map(& &1["name"]) |> Enum.join(", "),
      album: track["album"]["name"],
      album_art:
        track["album"]["images"]
        |> List.first()
        |> then(&(&1 && &1["url"])),
      uri: track["uri"]
    }
  end
end
