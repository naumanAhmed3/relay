defmodule Relay.Store do
  @moduledoc """
  The single source of truth for current pipeline state — a bounded
  ring buffer of recent events and alerts plus running counters. A
  LiveView reads a `snapshot/0` when it mounts; the live feed itself
  arrives over PubSub.
  """

  use GenServer
  alias Relay.{Alert, Event}

  @max_events 200
  @max_alerts 60
  @rate_window_ms 60_000

  @type stats :: %{
          total_events: non_neg_integer(),
          total_alerts: non_neg_integer(),
          rate_per_min: non_neg_integer(),
          by_type: %{optional(atom()) => non_neg_integer()},
          uptime_s: non_neg_integer()
        }

  # ── API ────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Record a processed event and its alerts; returns fresh stats."
  @spec record(Event.t(), [Alert.t()]) :: stats()
  def record(event, alerts), do: GenServer.call(__MODULE__, {:record, event, alerts})

  @doc "Current events, alerts and stats — used to seed a new dashboard."
  @spec snapshot() :: %{events: [Event.t()], alerts: [Alert.t()], stats: stats()}
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def init(:ok) do
    {:ok,
     %{
       events: [],
       alerts: [],
       total_events: 0,
       total_alerts: 0,
       by_type: %{},
       recent_ts: [],
       started_at: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_call({:record, event, alerts}, _from, state) do
    now = System.monotonic_time(:millisecond)

    state = %{
      state
      | events: [event | state.events] |> Enum.take(@max_events),
        alerts: (alerts ++ state.alerts) |> Enum.take(@max_alerts),
        total_events: state.total_events + 1,
        total_alerts: state.total_alerts + length(alerts),
        by_type: Map.update(state.by_type, event.type, 1, &(&1 + 1)),
        recent_ts: [now | state.recent_ts] |> Enum.filter(&(now - &1 <= @rate_window_ms))
    }

    {:reply, stats(state), state}
  end

  def handle_call(:snapshot, _from, state) do
    # events and alerts are kept newest-first.
    {:reply, %{events: state.events, alerts: state.alerts, stats: stats(state)}, state}
  end

  # ── Internals ──────────────────────────────────────────────

  defp stats(state) do
    %{
      total_events: state.total_events,
      total_alerts: state.total_alerts,
      rate_per_min: length(state.recent_ts),
      by_type: state.by_type,
      uptime_s: div(System.monotonic_time(:millisecond) - state.started_at, 1000)
    }
  end
end
