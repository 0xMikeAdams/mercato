defmodule Mercato.Orders.StatusMachine do
  @moduledoc """
  The order status state machine: the canonical set of statuses and the allowed
  transitions between them.

  This is the single source of truth — `Mercato.Orders.Order` validates against it
  (`statuses/0` for inclusion, `transition_allowed?/2` for transitions) rather than
  duplicating the rules.

  Transitions:

      pending    -> processing | cancelled | failed
      processing -> completed  | cancelled | failed
      completed  -> refunded
      failed     -> pending
      cancelled  -> (terminal)
      refunded   -> (terminal)
  """

  @statuses ~w(pending processing completed cancelled refunded failed)

  @doc "All valid order statuses."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Whether a status string is one Mercato recognizes."
  @spec status?(String.t()) :: boolean()
  def status?(status), do: status in @statuses

  @doc "Whether moving from `from` to `to` is an allowed transition."
  @spec transition_allowed?(String.t() | nil, String.t()) :: boolean()
  def transition_allowed?("pending", to) when to in ~w(processing cancelled failed), do: true
  def transition_allowed?("processing", to) when to in ~w(completed cancelled failed), do: true
  def transition_allowed?("completed", to) when to in ~w(refunded), do: true
  def transition_allowed?("failed", to) when to in ~w(pending), do: true
  def transition_allowed?("cancelled", _to), do: false
  def transition_allowed?("refunded", _to), do: false
  def transition_allowed?(_from, _to), do: false
end
