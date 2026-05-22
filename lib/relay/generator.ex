defmodule Relay.Generator do
  @moduledoc """
  Synthesises a continuous stream of realistic access events and feeds
  them into the pipeline. In a production system this would be a
  webhook receiver or a Kafka consumer; here it is a self-driving
  source so the dashboard always has something live to show.
  """

  use GenServer
  alias Relay.Event

  @actors [
    "Ada Bryce", "Leo Mensah", "Mei Tan", "Omar Haddad", "Nina Park",
    "Raj Patel", "Sara Lund", "Tom Frost", "Eve Wong", "Carl Reyes",
    "Hana Sato", "Jack Doyle", "Iris Vance", "Noah Kim", "Priya Rao"
  ]

  @apps ~w(GitHub AWS Okta Salesforce Slack Stripe Workday Datadog Notion Zoom)

  # Weighted toward common, low-risk events.
  @countries ~w(US US US US US US GB GB DE IN CA BR NG SG AU)

  @roles ~w(Engineer Engineer Analyst Manager Contractor Viewer Admin)

  @entitlements [
    "Repo Write", "Org Admin", "Billing Manager", "Prod Deploy",
    "Read-only", "Power User", "Payments Admin", "Security Admin"
  ]

  # Event-type frequency — logins are common, SSO changes are rare.
  @type_pool ~w(login login login login grant grant grant revoke
                login_failed login_failed role_change mfa_enrolled
                api_key sso_config)a

  @min_ms 650
  @max_ms 1500

  # ── API ────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Stop emitting events."
  def pause, do: GenServer.cast(__MODULE__, :pause)

  @doc "Resume emitting events."
  def resume, do: GenServer.cast(__MODULE__, :resume)

  @doc "Inject a burst of `n` events immediately."
  def burst(n \\ 8), do: GenServer.cast(__MODULE__, {:burst, n})

  @doc "Whether the generator is currently emitting."
  def running?, do: GenServer.call(__MODULE__, :running?)

  @doc "Build one synthetic event (also used to seed the dashboard)."
  @spec build_event() :: Event.t()
  def build_event do
    type = Enum.random(@type_pool)
    {action, target} = describe(type)

    %Event{
      id: Event.new_id(),
      at: DateTime.utc_now(),
      type: type,
      actor: Enum.random(@actors),
      actor_role: Enum.random(@roles),
      action: action,
      target: target,
      app: Enum.random(@apps),
      ip: random_ip(),
      country: Enum.random(@countries),
      severity: nil
    }
  end

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def init(:ok) do
    schedule()
    {:ok, %{enabled: true}}
  end

  @impl true
  def handle_cast(:pause, state), do: {:noreply, %{state | enabled: false}}
  def handle_cast(:resume, state), do: {:noreply, %{state | enabled: true}}

  def handle_cast({:burst, n}, state) do
    for _ <- 1..n, do: Relay.Pipeline.ingest(build_event())
    {:noreply, state}
  end

  @impl true
  def handle_call(:running?, _from, state), do: {:reply, state.enabled, state}

  @impl true
  def handle_info(:tick, state) do
    if state.enabled, do: Relay.Pipeline.ingest(build_event())
    schedule()
    {:noreply, state}
  end

  # ── Internals ──────────────────────────────────────────────

  defp schedule, do: Process.send_after(self(), :tick, Enum.random(@min_ms..@max_ms))

  defp describe(:login), do: {"signed in", nil}
  defp describe(:login_failed), do: {"failed a sign-in attempt", nil}
  defp describe(:mfa_enrolled), do: {"enrolled in MFA", nil}
  defp describe(:api_key), do: {"created an API key", "API key"}
  defp describe(:sso_config), do: {"modified SSO configuration", "SSO connection"}

  defp describe(:grant) do
    ent = Enum.random(@entitlements)
    {"was granted #{ent}", ent}
  end

  defp describe(:revoke) do
    ent = Enum.random(@entitlements)
    {"had #{ent} revoked", ent}
  end

  defp describe(:role_change) do
    role = Enum.random(@roles)
    {"role changed to #{role}", role}
  end

  defp random_ip do
    "#{Enum.random(1..223)}.#{Enum.random(0..255)}.#{Enum.random(0..255)}.#{Enum.random(1..254)}"
  end
end
