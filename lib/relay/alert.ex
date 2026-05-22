defmodule Relay.Alert do
  @moduledoc """
  An alert raised by a detection rule while processing an event.
  """

  @enforce_keys [:id, :at, :rule, :severity, :title]
  defstruct [:id, :at, :rule, :severity, :title, :detail, :actor, :event_id]

  @type t :: %__MODULE__{
          id: String.t(),
          at: DateTime.t(),
          rule: atom(),
          severity: Relay.Event.severity(),
          title: String.t(),
          detail: String.t() | nil,
          actor: String.t() | nil,
          event_id: String.t() | nil
        }

  @doc "A fresh, process-unique alert id."
  @spec new_id() :: String.t()
  def new_id do
    "al_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
