defmodule MusicDanceExperience.Spotify do
  alias MusicDanceExperience.SpotifyToken
  require Logger

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

    Logger.info("[Spotify] Exchanging OAuth code for tokens")

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
      Logger.info(
        "[Spotify] OAuth exchange succeeded; refresh_token_present=#{not is_nil(resp.body["refresh_token"])} expires_in=#{resp.body["expires_in"]}"
      )

      {:ok, resp.body["access_token"], resp.body["refresh_token"], resp.body["expires_in"]}
    else
      Logger.warning(
        "[Spotify] OAuth exchange failed: status=#{resp.status} body=#{inspect(loggable_body(resp.body))}"
      )

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
        Logger.warning(
          "[Spotify] search failed: status=#{resp.status} query=#{inspect(query)} body=#{inspect(loggable_body(resp.body))}"
        )

        {:error, {:spotify_http, :search, resp.status}}
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

        resp.status == 404 ->
          Logger.warning(
            "[Spotify] queue_track failed: no active device for uri=#{uri} body=#{inspect(loggable_body(resp.body))}"
          )

          {:error, :no_active_device}

        true ->
          Logger.warning(
            "[Spotify] queue_track failed: status=#{resp.status} uri=#{uri} body=#{inspect(loggable_body(resp.body))}"
          )

          {:error, {:spotify_http, :queue_track, resp.status}}
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
      resp =
        Req.get!("#{@api_base}/me/player/queue",
          headers: [authorization: "Bearer #{token}"]
        )

      if resp.status == 200 do
        tracks = resp.body["queue"] |> Enum.map(&format_track/1)
        {:ok, tracks}
      else
        Logger.warning(
          "[Spotify] queue fetch failed: status=#{resp.status} body=#{inspect(loggable_body(resp.body))}"
        )

        {:error, {:spotify_http, :queue, resp.status}}
      end
    end
  end

  @doc "Returns the currently playing track map, or nil if nothing is playing."
  def now_playing do
    with {:ok, token} <- SpotifyToken.get_token() do
      resp =
        Req.get!("#{@api_base}/me/player/currently-playing",
          headers: [authorization: "Bearer #{token}"]
        )

      cond do
        resp.status == 200 && resp.body["item"] ->
          maybe_log_devices(token, resp.body)
          {:ok, format_currently_playing(resp.body)}

        resp.status == 204 ->
          {:ok, nil}

        true ->
          Logger.warning(
            "[Spotify] now_playing failed: status=#{resp.status} body=#{inspect(loggable_body(resp.body))}"
          )

          {:error, {:spotify_http, :currently_playing, resp.status}}
      end
    end
  end

  # --- Private ---

  defp loggable_body(body) when is_map(body) do
    Map.take(body, ["error", "error_description", "message"])
  end

  defp loggable_body(body), do: body

  defp maybe_log_devices(token, body) do
    device = body["device"] || %{}

    if Enum.all?(["id", "name", "type", "is_active", "volume_percent"], &is_nil(device[&1])) do
      Logger.warning(
        "[Spotify] currently-playing returned no device metadata; top_level_keys=#{inspect(Map.keys(body) |> Enum.sort())}"
      )

      log_available_devices(token)
    end
  end

  defp log_available_devices(token) do
    resp =
      Req.get!("#{@api_base}/me/player/devices",
        headers: [authorization: "Bearer #{token}"]
      )

    if resp.status == 200 do
      devices =
        Enum.map(resp.body["devices"] || [], fn device ->
          %{
            id: device["id"],
            is_active: device["is_active"],
            is_private_session: device["is_private_session"],
            is_restricted: device["is_restricted"],
            name: device["name"],
            type: device["type"],
            volume_percent: device["volume_percent"]
          }
        end)

      Logger.info("[Spotify] Available devices snapshot: #{inspect(devices)}")
    else
      Logger.warning(
        "[Spotify] devices fetch failed: status=#{resp.status} body=#{inspect(loggable_body(resp.body))}"
      )
    end
  end

  defp format_currently_playing(body) do
    track = format_track(body["item"])
    device = body["device"] || %{}

    Map.merge(track, %{
      is_playing: body["is_playing"],
      progress_ms: body["progress_ms"],
      device: %{
        id: device["id"],
        name: device["name"],
        type: device["type"],
        is_active: device["is_active"],
        volume_percent: device["volume_percent"]
      }
    })
  end

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
