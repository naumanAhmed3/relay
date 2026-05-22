defmodule Relay.Event do
  @moduledoc """
  An access event flowing through the pipeline — one thing that
  happened to an identity in a connected application.
  """

  @enforce_keys [:id, :at, :type, :actor, :action]
  defstruct [
    :id,
    :at,
    :type,
    :actor,
    :actor_role,
    :action,
    :target,
    :app,
    :ip,
    :country,
    :severity
  ]

  @type type ::
          :login
          | :login_failed
          | :grant
          | :revoke
          | :role_change
          | :mfa_enrolled
          | :api_key
          | :sso_config

  @type severity :: :info | :notice | :warning | :critical

  @type t :: %__MODULE__{
          id: String.t(),
          at: DateTime.t(),
          type: type(),
          actor: String.t(),
          actor_role: String.t() | nil,
          action: String.t(),
          target: String.t() | nil,
          app: String.t() | nil,
          ip: String.t() | nil,
          country: String.t() | nil,
          severity: severity() | nil
        }

  @doc "A fresh, process-unique, sortable event id."
  @spec new_id() :: String.t()
  def new_id do
    "ev_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
