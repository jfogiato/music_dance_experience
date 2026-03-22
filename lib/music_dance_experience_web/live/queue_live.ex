defmodule MusicDanceExperienceWeb.QueueLive do
  use MusicDanceExperienceWeb, :live_view
  require Logger

  alias MusicDanceExperience.{Spotify, SpotifyToken, QueueAgent}
  alias MusicDanceExperienceWeb.Presence

  @presence_topic "queue:presence"

  @impl true
  def mount(_params, session, socket) do
    username = Map.get(session, "username", "UNKNOWN EMPLOYEE")

    if connected?(socket) do
      Logger.info("[QueueLive] Tracking presence for username=#{inspect(username)}")
      Phoenix.PubSub.subscribe(MusicDanceExperience.PubSub, QueueAgent.topic())
      Presence.track(self(), @presence_topic, username, %{})
      MusicDanceExperienceWeb.Endpoint.subscribe(@presence_topic)
    end

    online_users = if connected?(socket), do: Presence.list(@presence_topic) |> Map.keys(), else: []

    {:ok,
     socket
     |> assign(:username, username)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:queue, QueueAgent.list())
     |> assign(:searching, false)
     |> assign(:now_playing, MusicDanceExperience.QueuePoller.now_playing())
     |> assign(:spotify_connected, SpotifyToken.connected?())
     |> assign(:online_users, online_users)
     |> assign(:page_title, "Music Dance Experience")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, assign(socket, search_results: [], search_query: "")}
    else
      send(self(), {:do_search, query})
      {:noreply, assign(socket, search_query: query, searching: true)}
    end
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_results: [], search_query: "")}
  end

  @impl true
  def handle_event("queue_track", params, socket) do
    %{"uri" => uri, "name" => name, "artist" => artist, "album_art" => album_art} = params
    track = %{name: name, artist: artist, uri: uri, album_art: album_art || ""}

    case Spotify.queue_track(uri) do
      :ok ->
        QueueAgent.add_track(track, socket.assigns.username)

        {:noreply,
         socket
         |> assign(:search_results, [])
         |> assign(:search_query, "")
         |> put_flash(:info, "\"#{name}\" HAS BEEN SUBMITTED. YOUR CONTRIBUTION IS VALUED.")}

      {:error, :not_connected} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "SPOTIFY NOT CONNECTED. THE HOST MUST COMPLETE INTEGRATION."
         )}

      {:error, :no_active_device} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "NO ACTIVE PLAYBACK DETECTED. PLEASE NOTIFY YOUR WELLNESS COUNSELOR."
         )}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "CONTRIBUTION COULD NOT BE PROCESSED. PLEASE TRY AGAIN.")}
    end
  end

  @impl true
  def handle_info({:do_search, query}, socket) do
    case Spotify.search(query) do
      {:ok, tracks} ->
        {:noreply, assign(socket, search_results: tracks, searching: false)}

      {:error, :not_connected} ->
        {:noreply,
         socket
         |> assign(searching: false)
         |> put_flash(:error, "SPOTIFY NOT CONNECTED. THE HOST MUST COMPLETE INTEGRATION.")}

      {:error, _} ->
        {:noreply, assign(socket, search_results: [], searching: false)}
    end
  end

  @impl true
  def handle_info({:track_queued, entry}, socket) do
    {:noreply, assign(socket, queue: socket.assigns.queue ++ [entry])}
  end

  @impl true
  def handle_info({:track_removed, id}, socket) do
    {:noreply, assign(socket, queue: Enum.reject(socket.assigns.queue, &(&1.id == id)))}
  end

  @impl true
  def handle_info({:now_playing, track}, socket) do
    {:noreply, assign(socket, now_playing: track)}
  end

  @impl true
  def handle_info(:queue_reset, socket) do
    {:noreply, assign(socket, queue: QueueAgent.list())}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    online_users = Presence.list(@presence_topic) |> Map.keys()
    {:noreply, assign(socket, online_users: online_users)}
  end

  @impl true
  def terminate(reason, socket) do
    Logger.info(
      "[QueueLive] Terminating LiveView for username=#{inspect(socket.assigns.username)} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-lumon-cream">

      <%!-- Header --%>
      <header class="border-b border-lumon-teal/20 bg-white/60 backdrop-blur-sm sticky top-0 z-10">
        <div class="max-w-3xl mx-auto px-4 py-4 flex items-center justify-between">
          <div>
            <p class="text-xs font-mono tracking-[0.3em] text-lumon-teal uppercase">Lumon Industries</p>
            <h1 class="text-lg font-mono font-bold text-lumon-dark tracking-tight uppercase leading-tight">
              Music Dance Experience
            </h1>
          </div>
          <div class="text-right">
            <p class="text-xs font-mono text-lumon-mid tracking-wide uppercase">
              Employee: <span class="text-lumon-dark"><%= @username %></span>
            </p>
            <div class="flex items-center gap-3 justify-end mt-1">
              <%= if @spotify_connected do %>
                <span class="text-xs font-mono text-lumon-teal tracking-wide">● Spotify Active</span>
              <% else %>
                <a href="/auth/spotify" class="text-xs font-mono text-red-400 tracking-wide hover:text-red-600">
                  ⚠ Connect Spotify
                </a>
              <% end %>
              <a href="/logout" class="text-xs font-mono text-lumon-mid/60 hover:text-lumon-mid tracking-widest uppercase">
                Exit
              </a>
            </div>
          </div>
        </div>
      </header>

      <%!-- Online employees --%>
      <%= if length(@online_users) > 0 do %>
        <div class="border-b border-lumon-teal/10 bg-lumon-teal/[0.03]">
          <div class="max-w-3xl mx-auto px-4 py-1.5 flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-lumon-teal/50 flex-shrink-0"></span>
            <p class="font-mono text-[10px] text-lumon-mid/50 tracking-[0.15em] uppercase truncate">
              <%= length(@online_users) %> <%= if length(@online_users) == 1, do: "employee", else: "employees" %> online —
              <span class="text-lumon-mid/40"><%= Enum.join(@online_users, " · ") %></span>
            </p>
          </div>
        </div>
      <% end %>

      <main class="max-w-3xl mx-auto px-4 py-8 space-y-8">

        <%!-- Flash messages --%>
        <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
          <div class="border border-lumon-teal/40 bg-lumon-teal/5 px-4 py-3 font-mono text-xs text-lumon-teal tracking-wider uppercase">
            ✓ <%= msg %>
          </div>
        <% end %>

        <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
          <div class="border border-red-300 bg-red-50 px-4 py-3 font-mono text-xs text-red-600 tracking-wider uppercase">
            ⚠ <%= msg %>
          </div>
        <% end %>

        <%!-- Now Playing --%>
        <%= if @now_playing do %>
          <section>
            <h2 class="text-xs font-mono tracking-[0.4em] text-lumon-mid uppercase mb-4">
              Now Playing
            </h2>
            <div class="border border-lumon-teal/40 bg-white flex items-center gap-4 px-4 py-4">
              <%= if @now_playing.album_art do %>
                <img src={@now_playing.album_art} alt="" class="w-14 h-14 flex-shrink-0 object-cover" />
              <% else %>
                <div class="w-14 h-14 flex-shrink-0 bg-lumon-teal/10 flex items-center justify-center">
                  <span class="text-lumon-teal/40 font-mono text-lg">♪</span>
                </div>
              <% end %>
              <div class="flex-1 min-w-0">
                <p class="font-mono text-sm font-bold text-lumon-dark truncate"><%= @now_playing.name %></p>
                <p class="font-mono text-xs text-lumon-mid truncate"><%= @now_playing.artist %></p>
              </div>
              <span class="flex-shrink-0 w-2 h-2 rounded-full bg-lumon-teal animate-pulse"></span>
            </div>
          </section>
        <% end %>

        <%!-- Search section --%>
        <section>
          <h2 class="text-xs font-mono tracking-[0.4em] text-lumon-mid uppercase mb-4">
            Song Inquiry Terminal
          </h2>

          <form phx-change="search" phx-submit="search" class="relative">
            <input
              type="text"
              name="query"
              value={@search_query}
              phx-debounce="350"
              class="w-full bg-white border border-lumon-teal/40 px-4 py-3 pr-10 font-mono text-sm text-lumon-dark tracking-wide focus:outline-none focus:border-lumon-teal focus:ring-1 focus:ring-lumon-teal placeholder-lumon-mid/40"
              placeholder="Search for a song to contribute..."
              autocomplete="off"
            />
            <%= if @searching do %>
              <div class="absolute right-3 top-1/2 -translate-y-1/2">
                <div class="w-4 h-4 border-2 border-lumon-teal/30 border-t-lumon-teal rounded-full animate-spin"></div>
              </div>
            <% end %>
          </form>

          <%!-- Search results --%>
          <%= if @search_results != [] do %>
            <div class="mt-2 border border-lumon-teal/20 bg-white divide-y divide-lumon-teal/10">
              <%= for track <- @search_results do %>
                <div class="flex items-center gap-3 px-4 py-3 hover:bg-lumon-cream/60 transition-colors group">
                  <%= if track.album_art do %>
                    <img src={track.album_art} alt="" class="w-10 h-10 flex-shrink-0 object-cover" />
                  <% else %>
                    <div class="w-10 h-10 flex-shrink-0 bg-lumon-teal/10 flex items-center justify-center">
                      <span class="text-lumon-teal/40 font-mono text-xs">♪</span>
                    </div>
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <p class="font-mono text-sm text-lumon-dark truncate"><%= track.name %></p>
                    <p class="font-mono text-xs text-lumon-mid truncate"><%= track.artist %></p>
                  </div>
                  <button
                    phx-click="queue_track"
                    phx-value-uri={track.uri}
                    phx-value-name={track.name}
                    phx-value-artist={track.artist}
                    phx-value-album_art={track.album_art || ""}
                    class="flex-shrink-0 bg-lumon-teal text-white font-mono text-xs tracking-[0.2em] uppercase px-3 py-2 hover:bg-lumon-teal/90 transition-colors opacity-0 group-hover:opacity-100 focus:opacity-100"
                  >
                    Queue
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>

        <%!-- Queue display --%>
        <section>
          <h2 class="text-xs font-mono tracking-[0.4em] text-lumon-mid uppercase mb-4">
            Upcoming Refinements
            <span class="ml-2 text-lumon-teal"><%= length(@queue) %></span>
          </h2>

          <%= if @queue == [] do %>
            <div class="border border-lumon-teal/20 bg-white/50 px-6 py-10 text-center">
              <p class="font-mono text-sm text-lumon-mid/60 tracking-wide">
                The queue is empty. Contribute a song to begin the experience.
              </p>
            </div>
          <% else %>
            <div class="border border-lumon-teal/20 bg-white divide-y divide-lumon-teal/10">
              <%= for {entry, idx} <- Enum.with_index(@queue) do %>
                <div class="flex items-center gap-3 px-4 py-3">
                  <span class="font-mono text-xs text-lumon-mid/40 w-6 text-right flex-shrink-0">
                    <%= idx + 1 %>
                  </span>
                  <%= if entry.album_art && entry.album_art != "" do %>
                    <img src={entry.album_art} alt="" class="w-8 h-8 flex-shrink-0 object-cover" />
                  <% else %>
                    <div class="w-8 h-8 flex-shrink-0 bg-lumon-teal/10"></div>
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <p class="font-mono text-sm text-lumon-dark truncate"><%= entry.track_name %></p>
                    <p class="font-mono text-xs text-lumon-mid truncate"><%= entry.artist %></p>
                  </div>
                  <span class="flex-shrink-0 font-mono text-xs text-lumon-teal/60 tracking-wide">
                    <%= entry.username %>
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>

      </main>

      <footer class="mt-16 pb-8 text-center">
        <p class="font-mono text-xs text-lumon-mid/30 tracking-widest uppercase">
          Frolic, Mailce, Woe, and Dread — The Four Tempers
        </p>
      </footer>
    </div>
    """
  end
end
