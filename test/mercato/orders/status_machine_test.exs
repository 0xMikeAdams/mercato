defmodule Mercato.Orders.StatusMachineTest do
  use ExUnit.Case, async: true

  alias Mercato.Orders.StatusMachine

  test "statuses/0 lists the six order statuses" do
    assert Enum.sort(StatusMachine.statuses()) ==
             ~w(cancelled completed failed pending processing refunded)
  end

  test "status?/1 recognizes known statuses only" do
    assert StatusMachine.status?("pending")
    refute StatusMachine.status?("bogus")
  end

  describe "transition_allowed?/2" do
    test "allows the valid transitions" do
      assert StatusMachine.transition_allowed?("pending", "processing")
      assert StatusMachine.transition_allowed?("pending", "cancelled")
      assert StatusMachine.transition_allowed?("pending", "failed")
      assert StatusMachine.transition_allowed?("processing", "completed")
      assert StatusMachine.transition_allowed?("processing", "cancelled")
      assert StatusMachine.transition_allowed?("completed", "refunded")
      assert StatusMachine.transition_allowed?("failed", "pending")
    end

    test "rejects skips and backward moves" do
      refute StatusMachine.transition_allowed?("pending", "completed")
      refute StatusMachine.transition_allowed?("completed", "processing")
      refute StatusMachine.transition_allowed?("processing", "pending")
    end

    test "cancelled and refunded are terminal" do
      refute StatusMachine.transition_allowed?("cancelled", "pending")
      refute StatusMachine.transition_allowed?("refunded", "pending")
    end

    test "unknown/nil from-status is rejected" do
      refute StatusMachine.transition_allowed?(nil, "pending")
      refute StatusMachine.transition_allowed?("bogus", "pending")
    end
  end
end
