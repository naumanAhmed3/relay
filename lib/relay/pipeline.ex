defmodule Relay.Pipeline do
  @moduledoc """
  The processing stage. Every ingested event is enriched with a
  severity, run through the detection rules against a rolling window
  of recent events, recorded in the store, and broadcast to every
  connected dashboard over PubSub.
  """

  use GenServer
  alias Relay.{Event, Rules, Store}

  @topic "pipeline"
  @window 150

  @rank %{info: 0, notice: 1, warning: 2, critical: 3}
  @base %{
    login: :info,
    mfa_enrolled: :info,
    login_failed: :notice,
    grant: :notice,
    revoke: :notice,
    role_change: :notice,
    api_key: :notice,
    sso_config: :warning
  }

  # ── API ────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Submit a raw event into the pipeline."
  @spec ingest(Event.t()) :: :ok
  def ingest(%Event{} = event), do: GenServer.cast(__MODULE__, {:ingest, event})

  @doc "The PubSub topic carrying processed events."
  def topic, do: @topic

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def init(:ok), do: {:ok, %{window: []}}

  @impl true
  def handle_cast({:ingest, event}, %{window: window} = state) do
    alerts = Rules.evaluate(event, window)
    enriched = %{event | severity: severity(event, alerts)}
    stats = Store.record(enriched, alerts)

    Phoenix.PubSub.broadcast(
      Relay.PubSub,
      @topic,
      {:pipeline, enriched, alerts, stats}
    )

    {:noreply, %{state | window: Enum.take([enriched | window], @window)}}
  end

  # ── Internals ──────────────────────────────────────────────

  # An event's severity is the highest of its baseline and any alert
  # raised against it.
  defp severity(event, alerts) do
    base = Map.get(@base, event.type, :info)

    [base | Enum.map(alerts, & &1.severity)]
    |> Enum.max_by(&@rank[&1])
  end
end
