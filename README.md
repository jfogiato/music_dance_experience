# Music Dance Experience

A Severance-themed collaborative Spotify queue app. Guests pick a Lumon-issued employee name, enter the access code, and submit songs to the host's Spotify queue — all in real time.

---

## How it works

- The **host** connects their Spotify account via OAuth and sets an `APP_PASSWORD`
- **Guests** visit the app, choose (or accept a suggested) Severance-themed username, and enter the access code
- Guests search for songs and submit them directly to the host's Spotify queue
- The **Upcoming Refinements** list updates live for all connected users via Phoenix PubSub
- **Now Playing** shows the current track and updates automatically as songs change
- Songs are removed from the queue as Spotify plays through them, with a fallback reconciliation against Spotify's actual queue every 5 seconds to catch skips

---

## Setup

### Prerequisites

- Elixir / Erlang
- A [Spotify Developer app](https://developer.spotify.com/dashboard) with your redirect URI whitelisted
- A Spotify Premium account (required for the queue API)

### Dev

1. Clone the repo and install dependencies:
   ```sh
   mix setup
   ```

2. Set credentials in `config/dev.exs`:
   ```elixir
   config :music_dance_experience,
     spotify_client_id: "...",
     spotify_client_secret: "...",
     spotify_redirect_uri: "http://127.0.0.1:4000/auth/spotify/callback",
     app_password: "lumon"
   ```

   > **Note:** Spotify requires `127.0.0.1` — `localhost` is not allowed as a redirect URI.

3. Start the server:
   ```sh
   iex -S mix phx.server
   ```

4. Visit `http://127.0.0.1:4000` and connect Spotify via the **Connect Spotify** link in the header.

### Prod

Set the following environment variables:

| Variable | Description |
|---|---|
| `SECRET_KEY_BASE` | Phoenix secret key (`mix phx.gen.secret`) |
| `PHX_HOST` | Your domain (e.g. `mde.fogiato.com`) |
| `PORT` | HTTP port (default `4000`) |
| `SPOTIFY_CLIENT_ID` | From your Spotify Developer app |
| `SPOTIFY_CLIENT_SECRET` | From your Spotify Developer app |
| `SPOTIFY_REDIRECT_URI` | e.g. `https://mde.fogiato.com/auth/spotify/callback` |
| `APP_PASSWORD` | Access code guests use to log in |

Then run:
```sh
PHX_SERVER=true bin/music_dance_experience start
```

---

## Spotify notes

- **Development Mode limit:** By default, Spotify apps are in dev mode and cap at 25 authorized users. Since only the host authorizes, this is a non-issue unless you're running multiple host accounts.
- **Premium required:** The `/me/player/queue` endpoint requires a Spotify Premium account.
- **Active device:** Spotify must have an active player open on the host's device when the first track is queued. If playback is paused or closed, guests will see a "no active device" error.
- **Token is in-memory:** If the server restarts, the host needs to re-authorize at `/auth/spotify`. On re-auth, the app automatically seeds the local queue from Spotify's current upcoming queue.

---

## Architecture

| Module | Role |
|---|---|
| `Spotify` | Spotify Web API client (auth, search, queue, now playing) |
| `SpotifyToken` | GenServer holding access/refresh tokens, auto-refreshes on expiry |
| `QueueAgent` | In-memory Agent storing the live queue, broadcasts changes via PubSub |
| `QueuePoller` | GenServer polling Spotify every 5s to update now playing and reconcile the queue |
| `QueueLive` | Phoenix LiveView — the main UI, subscribed to PubSub for real-time updates |
| `AuthController` | Handles guest login, logout, and Spotify OAuth callback |
| `RequireAuth` | Plug guarding all routes behind the access code session |
