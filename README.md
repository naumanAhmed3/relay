# Relay — Real-time Access-Events Pipeline

Relay ingests a continuous stream of **access events** — sign-ins, grants,
revocations, role changes, SSO edits — runs them through a **detection
pipeline**, and pushes every processed event and alert to a **Phoenix
LiveView** dashboard the instant it happens. No polling: the server pushes.

It is built in **Elixir / OTP** — a supervised tree of GenServers connected by
`Phoenix.PubSub` — the model that makes soft-real-time systems on the BEAM
straightforward.

**Live demo:** https://relay-access-events.fly.dev

---

## What it does

A self-driving generator emits realistic access events. Each one flows through:

```
  Generator ──▶ Pipeline ──▶ Store ──▶ PubSub ──▶ LiveView dashboards
  (GenServer)   (GenServer)  (GenServer  (broadcast)  (every connected
   timer-driven  enrich +     + ring                   browser, pushed)
   event source  detect       buffer)
```

1. **Generator** — a `GenServer` that synthesises an event every ~1s (and on
   demand: *Inject burst*). In production this seat would be a webhook
   receiver or a Kafka consumer.
2. **Pipeline** — enriches each event with a **severity**, evaluates it against
   six **detection rules** over a rolling window of recent events, and
   broadcasts the result.
3. **Store** — a `GenServer` holding a bounded ring buffer of recent events and
   alerts plus running counters; it is the single source of truth a freshly
   connected dashboard reads from.
4. **LiveView** — subscribes to the pipeline's PubSub topic and renders the
   live feed with [LiveView streams](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4),
   so the DOM updates are minimal and bounded.

Every piece is a child of the application's **supervision tree** — if any
process crashes it is restarted, and the system keeps running.

### Detection rules

`Relay.Rules` is a pure module — each rule is a function of the incoming event
plus its recent context:

| Rule | Fires when | Severity |
|---|---|---|
| `after_hours` | a privileged change happens outside 07:00–19:00 UTC | warning |
| `rapid_grants` | one actor receives 3+ grants in quick succession | warning |
| `brute_force` | one actor has 3+ failed sign-ins in the window | critical |
| `privilege_escalation` | a grant of a high-risk entitlement or the Admin role | warning |
| `sso_change` | any SSO configuration is modified | critical |
| `new_geo` | an actor signs in from a country they have not used recently | warning |

---

## Why Elixir

This is the kind of system the BEAM was built for:

- **Concurrency** — the generator, pipeline, store, every LiveView socket and
  the PubSub fan-out are independent lightweight processes.
- **Fault tolerance** — a one-for-one supervisor restarts any crashed stage.
- **Soft real-time** — `Phoenix.PubSub` + LiveView push updates to every
  connected client over a single WebSocket, with server-rendered diffs.

No database is involved — the pipeline's working state lives in process memory
and a ring buffer, which is the right tool for a live event feed.

---

## Tech stack

- **Elixir 1.18** / **Erlang/OTP 27**
- **Phoenix 1.8** + **Phoenix LiveView 1.1**
- **Phoenix.PubSub** for the broadcast fan-out
- **Bandit** HTTP server · **Tailwind CSS v4**
- Deployed on **Fly.io** as an OTP release

---

## Project structure

```
relay/
├── lib/relay/
│   ├── event.ex         the access-event struct
│   ├── alert.ex         the alert struct
│   ├── generator.ex     GenServer — synthetic event source
│   ├── rules.ex         the six detection rules (pure)
│   ├── pipeline.ex      GenServer — enrich · detect · broadcast
│   ├── store.ex         GenServer — ring buffer + counters
│   └── application.ex   the supervision tree
├── lib/relay_web/
│   └── live/dashboard_live.ex   the real-time LiveView
├── Dockerfile           multi-stage OTP release build
└── fly.toml             Fly.io deployment config
```

---

## Run it locally

Requires Elixir 1.18+ / OTP 27.

```bash
mix setup
mix phx.server
```

Open http://localhost:4000 — events begin streaming immediately. Use **Pause**
to freeze the generator and **Inject burst** to fire a spike of ten events
(a quick way to trip `rapid_grants` and `brute_force`).

---

## Deployment

Relay ships as an OTP release in a multi-stage Docker image and runs on
[Fly.io](https://fly.io):

```bash
fly launch       # or: fly deploy --remote-only
```

`config/runtime.exs` reads `SECRET_KEY_BASE`, `PHX_HOST` and `PORT` at boot;
the release is started by `bin/server`. The Docker image is built on Fly's
remote builder, so no local Docker is needed.

---

## License

MIT
