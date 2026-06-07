defmodule Mercato.Subscriptions.SchedulerTest do
  # async: false — Scheduler is a named singleton GenServer and renewal processing
  # runs in its process, so it needs shared-mode sandbox access. It is started linked
  # and stopped synchronously within each test body so it never outlives the test
  # process (the sandbox connection owner).
  use ExUnit.Case, async: false

  alias Mercato.Repo
  alias Mercato.Subscriptions.Scheduler

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp start_scheduler!(opts) do
    {:ok, pid} = Scheduler.start_link(opts)
    pid
  end

  defp stop_scheduler(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 -> :ok
      end
    end
  end

  test "starts disabled by default with zeroed stats and no scheduled run" do
    pid = start_scheduler!([])

    status = Scheduler.get_status()
    refute status.enabled
    assert status.next_run == nil
    assert status.last_run == nil
    assert status.stats.total_processed == 0

    stop_scheduler(pid)
  end

  test "enable/disable are idempotent and update status" do
    pid = start_scheduler!([])

    assert :ok = Scheduler.enable()
    assert Scheduler.get_status().enabled
    assert :already_enabled = Scheduler.enable()

    assert :ok = Scheduler.disable()
    refute Scheduler.get_status().enabled
    assert :already_disabled = Scheduler.disable()

    stop_scheduler(pid)
  end

  test "process_renewals/0 returns 0 when nothing is due and records the run" do
    pid = start_scheduler!(batch_size: 10)

    assert Scheduler.process_renewals() == 0

    status = Scheduler.get_status()
    assert status.last_run != nil
    assert status.stats.last_run_processed == 0

    stop_scheduler(pid)
  end
end
