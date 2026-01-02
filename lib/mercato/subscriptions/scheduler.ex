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

  The scheduler is automatically started as part of the Mercato application
  supervision tree. It will run continuously and process renewals based on
  the configured interval.

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
  @default_enabled true

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
    # Get configuration from opts or application config
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
    app_config = Application.get_env(:mercato, __MODULE__, [])

    [
      interval: Keyword.get(opts, :interval, Keyword.get(app_config, :interval, @default_interval)),
      batch_size: Keyword.get(opts, :batch_size, Keyword.get(app_config, :batch_size, @default_batch_size)),
      enabled: Keyword.get(opts, :enabled, Keyword.get(app_config, :enabled, @default_enabled))
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

    # Get subscriptions due for renewal
    subscriptions = Subscriptions.get_subscriptions_due_for_renewal()
    total_count = length(subscriptions)

    Logger.info("Found #{total_count} subscriptions due for renewal")

    # Process subscriptions in batches
    {successful, failed} = process_subscriptions_in_batches(subscriptions, state.batch_size)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    Logger.info("""
    Subscription renewal processing completed:
    - Total processed: #{total_count}
    - Successful: #{successful}
    - Failed: #{failed}
    - Duration: #{duration}ms
    """)

    # Update stats
    new_stats = %{
      total_processed: state.stats.total_processed + total_count,
      total_successful: state.stats.total_successful + successful,
      total_failed: state.stats.total_failed + failed,
      last_run_processed: total_count,
      last_run_successful: successful,
      last_run_failed: failed
    }

    {total_count, new_stats}
    end
  end

  defp process_subscriptions_in_batches(subscriptions, batch_size) do
    subscriptions
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({0, 0}, fn batch, {successful_acc, failed_acc} ->
      {batch_successful, batch_failed} = process_subscription_batch(batch)
      {successful_acc + batch_successful, failed_acc + batch_failed}
    end)
  end

  defp process_subscription_batch(subscriptions) do
    Enum.reduce(subscriptions, {0, 0}, fn subscription, {successful, failed} ->
      case process_single_subscription(subscription) do
        {:ok, _order} ->
          {successful + 1, failed}

        {:error, reason} ->
          Logger.warning("Failed to process renewal for subscription #{subscription.id}: #{inspect(reason)}")
          {successful, failed + 1}
      end
    end)
  end

  defp process_single_subscription(subscription) do
    try do
      case Subscriptions.process_renewal(subscription.id) do
        {:ok, order} ->
          Logger.debug("Successfully processed renewal for subscription #{subscription.id}, created order #{order.id}")
          {:ok, order}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception processing renewal for subscription #{subscription.id}: #{inspect(error)}")
        {:error, error}
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
