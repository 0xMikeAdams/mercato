defmodule Mercato.Subscriptions.Scheduler do
  @moduledoc """
  GenServer for automated subscription renewal processing.

  This module runs periodic jobs to process subscription renewals. It queries
  for subscriptions that are due for renewal and creates orders automatically.

  ## Configuration

  The scheduler can be configured with the following options:

  - `:interval` - How often to check for renewals (default: 1 hour)
  - `:batch_size` - How many subscriptions to process per batch (default: 100)
  - `:enabled` - Whether the scheduler is enabled (default: true)

  ## Usage

  The scheduler is optional. Host applications may add it to their own
  supervision tree when they want an in-process renewal loop.

  ## Manual Processing

  You can also manually trigger renewal processing:

      Mercato.Subscriptions.Scheduler.process_renewals()

  ## Monitoring

  The scheduler logs information about renewal processing, including:

  - Number of subscriptions processed
  - Number of successful renewals
  - Number of failed renewals
  - Processing time
  """

  use GenServer
  require Logger

  alias Mercato
  alias Mercato.Subscriptions

  # Default configuration
  @default_interval :timer.hours(1)  # Check every hour
  @default_batch_size 100
  @default_enabled false

  ## Client API

  @doc """
  Starts the subscription scheduler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers renewal processing.

  Returns the number of subscriptions processed.
  """
  def process_renewals do
    GenServer.call(__MODULE__, :process_renewals)
  end

  @doc """
  Gets the current scheduler status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Enables the scheduler.
  """
  def enable do
    GenServer.call(__MODULE__, :enable)
  end

  @doc """
  Disables the scheduler.
  """
  def disable do
    GenServer.call(__MODULE__, :disable)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    config = get_config(opts)

    state = %{
      interval: config[:interval],
      batch_size: config[:batch_size],
      enabled: config[:enabled],
      timer_ref: nil,
      last_run: nil,
      stats: %{
        total_processed: 0,
        total_successful: 0,
        total_failed: 0,
        last_run_processed: 0,
        last_run_successful: 0,
        last_run_failed: 0
      }
    }

    # Schedule the first renewal check if enabled
    state = if state.enabled, do: schedule_next_check(state), else: state

    Logger.info("Subscription scheduler started with interval: #{state.interval}ms, enabled: #{state.enabled}")

    {:ok, state}
  end

  @impl true
  def handle_call(:process_renewals, _from, state) do
    {processed_count, new_stats} = do_process_renewals(state)
    new_state = %{state | stats: new_stats, last_run: DateTime.utc_now()}

    {:reply, processed_count, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: state.enabled,
      interval: state.interval,
      batch_size: state.batch_size,
      last_run: state.last_run,
      stats: state.stats,
      next_run: get_next_run_time(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:enable, _from, state) do
    if not state.enabled do
      new_state = %{state | enabled: true} |> schedule_next_check()
      Logger.info("Subscription scheduler enabled")
      {:reply, :ok, new_state}
    else
      {:reply, :already_enabled, state}
    end
  end

  @impl true
  def handle_call(:disable, _from, state) do
    if state.enabled do
      new_state = cancel_timer(%{state | enabled: false})
      Logger.info("Subscription scheduler disabled")
      {:reply, :ok, new_state}
    else
      {:reply, :already_disabled, state}
    end
  end

  @impl true
  def handle_info(:process_renewals, state) do
    if state.enabled do
      {_processed_count, new_stats} = do_process_renewals(state)
      new_state = %{state | stats: new_stats, last_run: DateTime.utc_now()}
      new_state = schedule_next_check(new_state)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle process monitoring if needed
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    cancel_timer(state)
    Logger.info("Subscription scheduler terminated: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp get_config(opts) do
    [
      interval: Keyword.get(opts, :interval, @default_interval),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      enabled: Keyword.get(opts, :enabled, @default_enabled)
    ]
  end

  defp schedule_next_check(state) do
    # Cancel existing timer if any
    state = cancel_timer(state)

    # Schedule next check
    timer_ref = Process.send_after(self(), :process_renewals, state.interval)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state
  defp cancel_timer(%{timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | timer_ref: nil}
  end

  defp do_process_renewals(state) do
    if not Mercato.repo_started?() do
      Logger.info("Subscription renewal processing skipped (repo not started)")
      {0, %{state.stats | last_run_processed: 0, last_run_successful: 0, last_run_failed: 0}}
    else
      start_time = System.monotonic_time(:millisecond)

      Logger.info("Starting subscription renewal processing")

      summary =
        case Subscriptions.process_due_renewals(batch_size: state.batch_size) do
          {:ok, %{lock_acquired?: false}} ->
            %{processed: 0, successful: 0, failed: 0}

          {:ok, result} ->
            result

          {:error, reason} ->
            Logger.error("Subscription renewal processing failed: #{inspect(reason)}")
            %{processed: 0, successful: 0, failed: 0}
        end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Logger.info("""
      Subscription renewal processing completed:
      - Total processed: #{summary.processed}
      - Successful: #{summary.successful}
      - Failed: #{summary.failed}
      - Duration: #{duration}ms
      """)

      new_stats = %{
        total_processed: state.stats.total_processed + summary.processed,
        total_successful: state.stats.total_successful + summary.successful,
        total_failed: state.stats.total_failed + summary.failed,
        last_run_processed: summary.processed,
        last_run_successful: summary.successful,
        last_run_failed: summary.failed
      }

      {summary.processed, new_stats}
    end
  end

  defp get_next_run_time(%{timer_ref: nil}), do: nil
  defp get_next_run_time(%{timer_ref: timer_ref}) do
    case Process.read_timer(timer_ref) do
      false -> nil
      time_left -> DateTime.add(DateTime.utc_now(), time_left, :millisecond)
    end
  end
end
