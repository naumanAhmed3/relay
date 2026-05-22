defmodule Relay.Rules do
  @moduledoc """
  The detection stage of the pipeline. Each rule is a pure function of
  the incoming event plus a window of recent events; `evaluate/2` runs
  them all and returns whatever alerts fired.
  """

  alias Relay.{Alert, Event}

  @high_risk ["Org Admin", "Security Admin", "Payments Admin", "Prod Deploy"]
  @threshold 3

  @doc "Run every rule against an event and its recent context."
  @spec evaluate(Event.t(), [Event.t()]) :: [Alert.t()]
  def evaluate(%Event{} = event, recent) do
    [
      &after_hours/2,
      &rapid_grants/2,
      &brute_force/2,
      &privilege_escalation/2,
      &sso_change/2,
      &new_geo/2
    ]
    |> Enum.map(& &1.(event, recent))
    |> Enum.reject(&is_nil/1)
  end

  @doc "The rules this pipeline runs, for display."
  def catalog do
    [
      {:after_hours, "Privileged changes outside business hours"},
      {:rapid_grants, "Several grants to one actor in quick succession"},
      {:brute_force, "Repeated failed sign-ins from one actor"},
      {:privilege_escalation, "A grant of a high-risk entitlement or Admin role"},
      {:sso_change, "Any change to an SSO configuration"},
      {:new_geo, "A sign-in from a country the actor has not used recently"}
    ]
  end

  # ── Rules ──────────────────────────────────────────────────

  defp after_hours(%Event{type: t} = e, _recent)
       when t in [:grant, :role_change, :sso_config, :api_key] do
    hour = e.at.hour

    if hour < 7 or hour >= 19 do
      alert(:after_hours, :warning, "Privileged change outside business hours",
        "#{e.actor} performed a #{t} action at #{pad(hour)}:#{pad(e.at.minute)} UTC.", e)
    end
  end

  defp after_hours(_event, _recent), do: nil

  defp rapid_grants(%Event{type: :grant} = e, recent) do
    count = 1 + Enum.count(recent, &(&1.type == :grant and &1.actor == e.actor))

    if count >= @threshold do
      alert(:rapid_grants, :warning, "Rapid access grants",
        "#{e.actor} has received #{count} grants in quick succession.", e)
    end
  end

  defp rapid_grants(_event, _recent), do: nil

  defp brute_force(%Event{type: :login_failed} = e, recent) do
    count = 1 + Enum.count(recent, &(&1.type == :login_failed and &1.actor == e.actor))

    if count >= @threshold do
      alert(:brute_force, :critical, "Possible brute-force sign-in",
        "#{e.actor} has #{count} failed sign-ins in the recent window.", e)
    end
  end

  defp brute_force(_event, _recent), do: nil

  defp privilege_escalation(%Event{type: :grant, target: target} = e, _recent)
       when target in @high_risk do
    alert(:privilege_escalation, :warning, "Privilege escalation",
      ~s(#{e.actor} was granted the high-risk entitlement "#{target}".), e)
  end

  defp privilege_escalation(%Event{type: :role_change, target: "Admin"} = e, _recent) do
    alert(:privilege_escalation, :warning, "Privilege escalation",
      "#{e.actor} was elevated to the Admin role.", e)
  end

  defp privilege_escalation(_event, _recent), do: nil

  defp sso_change(%Event{type: :sso_config} = e, _recent) do
    alert(:sso_change, :critical, "SSO configuration changed",
      "#{e.actor} modified the SSO connection on #{e.app} — confirm this was expected.", e)
  end

  defp sso_change(_event, _recent), do: nil

  defp new_geo(%Event{type: :login} = e, recent) do
    prior =
      recent
      |> Enum.filter(&(&1.type == :login and &1.actor == e.actor))
      |> Enum.map(& &1.country)

    if prior != [] and e.country not in prior do
      alert(:new_geo, :warning, "Sign-in from a new location",
        "#{e.actor} signed in from #{e.country}; recent sign-ins came from #{prior |> Enum.uniq() |> Enum.join(", ")}.",
        e)
    end
  end

  defp new_geo(_event, _recent), do: nil

  # ── Helpers ────────────────────────────────────────────────

  defp alert(rule, severity, title, detail, %Event{} = e) do
    %Alert{
      id: Alert.new_id(),
      at: e.at,
      rule: rule,
      severity: severity,
      title: title,
      detail: detail,
      actor: e.actor,
      event_id: e.id
    }
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
