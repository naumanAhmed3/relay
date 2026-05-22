defmodule RelayWeb.DashboardLive do
  @moduledoc """
  The live access-events dashboard. Subscribes to the pipeline's PubSub
  topic and renders every processed event and alert as it arrives, with
  no polling — the page is pushed updates by the server.
  """

  use RelayWeb, :live_view

  alias Relay.{Generator, Pipeline, Rules, Store}

  @feed_limit 60
  @alert_limit 30

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Relay.PubSub, Pipeline.topic())
    end

    %{events: events, alerts: alerts, stats: stats} = Store.snapshot()

    socket =
      socket
      |> assign(:page_title, "Relay")
      |> assign(:stats, stats)
      |> assign(:running, Generator.running?())
      |> assign(:rules, Rules.catalog())
      |> assign(:feed_limit, @feed_limit)
      |> stream(:events, Enum.take(events, @feed_limit), limit: @feed_limit)
      |> stream(:alerts, Enum.take(alerts, @alert_limit), limit: @alert_limit)

    {:ok, socket}
  end

  @impl true
  def handle_info({:pipeline, event, alerts, stats}, socket) do
    socket =
      socket
      |> assign(:stats, stats)
      |> stream_insert(:events, event, at: 0, limit: @feed_limit)

    socket =
      Enum.reduce(alerts, socket, fn alert, acc ->
        stream_insert(acc, :alerts, alert, at: 0, limit: @alert_limit)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    if socket.assigns.running, do: Generator.pause(), else: Generator.resume()
    {:noreply, assign(socket, :running, not socket.assigns.running)}
  end

  def handle_event("burst", _params, socket) do
    Generator.burst(10)
    {:noreply, socket}
  end

  # ── Render ─────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0b0d10] text-[#e7e8ec]">
      <header class="border-b border-[#1c1f26] sticky top-0 z-20 bg-[#0b0d10]/95 backdrop-blur">
        <div class="max-w-6xl mx-auto px-6 h-16 flex items-center gap-3">
          <span class="grid place-items-center w-9 h-9 rounded-lg bg-[#a3e635]/15 ring-1 ring-[#a3e635]/30">
            <svg viewBox="0 0 24 24" class="w-5 h-5 text-[#a3e635]" fill="none"
              stroke="currentColor" stroke-width="2" stroke-linecap="round">
              <path d="M4 12h4l3-8 4 16 3-8h2" />
            </svg>
          </span>
          <div>
            <h1 class="font-semibold tracking-tight leading-tight">Relay</h1>
            <p class="text-[11px] text-[#6b6f7a] leading-tight">
              real-time access-events pipeline
            </p>
          </div>
          <div class="ml-auto flex items-center gap-2 text-[12px] font-mono">
            <span class={[
              "w-2 h-2 rounded-full",
              @running && "bg-[#a3e635] animate-pulse",
              !@running && "bg-[#6b6f7a]"
            ]} />
            <span class="text-[#9aa0ab]">
              {if @running, do: "live", else: "paused"} · {@stats.rate_per_min}/min
            </span>
          </div>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-7">
        <%!-- Stat tiles --%>
        <section class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <.stat label="Events processed" value={@stats.total_events} />
          <.stat label="Events / min" value={@stats.rate_per_min} accent />
          <.stat label="Alerts raised" value={@stats.total_alerts} />
          <.stat label="Detection rules" value={length(@rules)} />
        </section>

        <div class="mt-6 grid lg:grid-cols-3 gap-5">
          <%!-- Event stream --%>
          <section class="lg:col-span-2">
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold text-[#c3c6cd]">Live event stream</h2>
              <div class="flex items-center gap-2">
                <button
                  phx-click="toggle"
                  class="text-[12px] rounded-lg ring-1 ring-[#2a2e38] px-2.5 h-8 text-[#9aa0ab] hover:text-white hover:ring-[#3a3f4c] transition"
                >
                  {if @running, do: "Pause", else: "Resume"}
                </button>
                <button
                  phx-click="burst"
                  class="text-[12px] font-medium rounded-lg bg-[#a3e635] text-[#0b0d10] px-3 h-8 hover:brightness-110 transition"
                >
                  Inject burst
                </button>
              </div>
            </div>
            <div
              id="events"
              phx-update="stream"
              class="rounded-xl ring-1 ring-[#1c1f26] divide-y divide-[#15181e] overflow-hidden"
            >
              <div
                :for={{dom_id, ev} <- @streams.events}
                id={dom_id}
                class="flex items-center gap-3 px-3.5 py-2.5 bg-[#101319]"
              >
                <span class="text-[11px] font-mono text-[#5f636e] w-[58px] shrink-0">
                  {clock(ev.at)}
                </span>
                <span class={[
                  "text-[9.5px] font-mono font-semibold tracking-wide rounded px-1.5 py-0.5 w-[64px] text-center shrink-0",
                  type_color(ev.type)
                ]}>
                  {type_label(ev.type)}
                </span>
                <span class="text-[13px] text-[#dfe1e6] flex-1 min-w-0 truncate">
                  <span class="font-medium text-white">{ev.actor}</span>
                  {ev.action}
                </span>
                <span class="text-[11px] text-[#7c818c] hidden sm:block shrink-0">
                  {ev.app}
                </span>
                <span class="text-[11px] font-mono text-[#5f636e] hidden md:block w-7 shrink-0">
                  {ev.country}
                </span>
                <span
                  class={["w-1.5 h-1.5 rounded-full shrink-0", sev_dot(ev.severity)]}
                  title={to_string(ev.severity)}
                />
              </div>
            </div>
            <p class="mt-2 text-[11px] text-[#5f636e]">
              Showing the most recent {@feed_limit} events · feed pushed over Phoenix PubSub.
            </p>
          </section>

          <%!-- Sidebar --%>
          <section class="space-y-5">
            <%!-- Alerts --%>
            <div>
              <h2 class="text-sm font-semibold text-[#c3c6cd] mb-3">Alerts</h2>
              <div
                id="alerts"
                phx-update="stream"
                class="space-y-2 min-h-[60px]"
              >
                <div
                  :for={{dom_id, al} <- @streams.alerts}
                  id={dom_id}
                  class="rounded-xl ring-1 ring-[#1c1f26] bg-[#101319] px-3.5 py-2.5"
                >
                  <div class="flex items-center gap-2">
                    <span class={[
                      "text-[9.5px] font-mono font-semibold rounded px-1.5 py-0.5",
                      sev_pill(al.severity)
                    ]}>
                      {String.upcase(to_string(al.severity))}
                    </span>
                    <span class="text-[11px] font-mono text-[#6b6f7a]">{al.rule}</span>
                    <span class="ml-auto text-[10px] font-mono text-[#4f535d]">
                      {clock(al.at)}
                    </span>
                  </div>
                  <div class="mt-1 text-[12.5px] font-medium text-[#e7e8ec]">
                    {al.title}
                  </div>
                  <div class="mt-0.5 text-[11.5px] text-[#82868f] leading-relaxed">
                    {al.detail}
                  </div>
                </div>
              </div>
              <p
                class="text-[12px] text-[#5f636e] rounded-xl ring-1 ring-dashed ring-[#1c1f26] px-3.5 py-4 text-center only:block hidden"
              >
                No alerts yet — the rules are watching.
              </p>
            </div>

            <%!-- Events by type --%>
            <div>
              <h2 class="text-sm font-semibold text-[#c3c6cd] mb-3">By event type</h2>
              <div class="rounded-xl ring-1 ring-[#1c1f26] bg-[#101319] divide-y divide-[#15181e]">
                <div
                  :for={{type, count} <- by_type_sorted(@stats.by_type)}
                  class="flex items-center gap-3 px-3.5 py-2"
                >
                  <span class={["w-1.5 h-1.5 rounded-full shrink-0", type_dot(type)]} />
                  <span class="text-[12px] text-[#b7bac2] flex-1">{type_label(type)}</span>
                  <span class="text-[12px] font-mono text-[#e7e8ec]">{count}</span>
                </div>
                <div
                  :if={@stats.by_type == %{}}
                  class="px-3.5 py-4 text-center text-[12px] text-[#5f636e]"
                >
                  warming up…
                </div>
              </div>
            </div>

            <%!-- Detection rules --%>
            <div>
              <h2 class="text-sm font-semibold text-[#c3c6cd] mb-3">Detection rules</h2>
              <div class="rounded-xl ring-1 ring-[#1c1f26] bg-[#101319] divide-y divide-[#15181e]">
                <div :for={{rule, desc} <- @rules} class="px-3.5 py-2">
                  <div class="text-[12px] font-mono text-[#a3e635]/90">{rule}</div>
                  <div class="text-[11px] text-[#7c818c] leading-relaxed">{desc}</div>
                </div>
              </div>
            </div>
          </section>
        </div>

        <footer class="mt-8 pt-5 border-t border-[#15181e] text-[11px] text-[#4f535d] leading-relaxed">
          A self-driving generator feeds synthetic access events into an OTP
          pipeline — enrichment, six detection rules, an ETS-backed store — and
          every connected dashboard is updated live over Phoenix PubSub. Built
          with Elixir, Phoenix and LiveView.
        </footer>
      </main>
    </div>
    """
  end

  # ── Function components ────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :accent, :boolean, default: false

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl ring-1 ring-[#1c1f26] bg-[#101319] px-4 py-3.5">
      <div class="text-[10.5px] uppercase tracking-wide text-[#6b6f7a]">{@label}</div>
      <div class={[
        "mt-1 text-2xl font-semibold tabular-nums",
        @accent && "text-[#a3e635]"
      ]}>
        {@value}
      </div>
    </div>
    """
  end

  # ── View helpers ───────────────────────────────────────────

  defp clock(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp type_label(type) do
    type |> to_string() |> String.replace("_", " ") |> String.upcase()
  end

  defp by_type_sorted(by_type) do
    by_type |> Enum.sort_by(fn {_t, c} -> -c end)
  end

  defp type_color(type) do
    case type do
      :login -> "text-sky-300 bg-sky-400/10"
      :login_failed -> "text-rose-300 bg-rose-400/10"
      :grant -> "text-[#a3e635] bg-[#a3e635]/10"
      :revoke -> "text-amber-300 bg-amber-400/10"
      :role_change -> "text-violet-300 bg-violet-400/10"
      :mfa_enrolled -> "text-teal-300 bg-teal-400/10"
      :api_key -> "text-blue-300 bg-blue-400/10"
      :sso_config -> "text-fuchsia-300 bg-fuchsia-400/10"
    end
  end

  defp type_dot(type) do
    case type do
      :login -> "bg-sky-400"
      :login_failed -> "bg-rose-400"
      :grant -> "bg-[#a3e635]"
      :revoke -> "bg-amber-400"
      :role_change -> "bg-violet-400"
      :mfa_enrolled -> "bg-teal-400"
      :api_key -> "bg-blue-400"
      :sso_config -> "bg-fuchsia-400"
    end
  end

  defp sev_dot(:critical), do: "bg-rose-500"
  defp sev_dot(:warning), do: "bg-amber-400"
  defp sev_dot(:notice), do: "bg-sky-400"
  defp sev_dot(_), do: "bg-[#3a3f4c]"

  defp sev_pill(:critical), do: "text-rose-300 bg-rose-500/15"
  defp sev_pill(:warning), do: "text-amber-300 bg-amber-400/15"
  defp sev_pill(:notice), do: "text-sky-300 bg-sky-400/15"
  defp sev_pill(_), do: "text-neutral-300 bg-neutral-500/15"
end
