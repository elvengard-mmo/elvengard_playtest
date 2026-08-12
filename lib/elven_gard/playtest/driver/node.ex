defmodule ElvenGard.Playtest.Driver.Node do
  @moduledoc """
  Supervises a line-delimited JSON driver process and correlates its commands.

  The Node process owns browser objects that cannot cross the VM boundary. This
  module exposes those objects as opaque string IDs and forwards asynchronous
  browser events to the test process that started the driver.
  """

  use GenServer

  require Logger

  @protocol_version 1
  @ready_timeout 10_000
  @shutdown_timeout 5_000
  @shutdown_id -1
  # Playwright's own action timeout defaults to 30 seconds. The transport must
  # outlive it so callers receive Playwright's structured error instead of an
  # unrelated GenServer timeout while a busy CI runner is still working.
  @command_timeout 60_000
  @max_line_size 4 * 1_024 * 1_024

  @type error :: %{required(String.t()) => Jason.Encoder.value()}
  @type option ::
          {:driver_path, Path.t()}
          | {:env, %{optional(String.t()) => String.t()}}
          | {:node_path, Path.t()}
          | {:owner, pid()}

  defstruct [:owner, :port, buffer: "", next_id: 0, pending: %{}]

  ## Public API

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec command(GenServer.server(), String.t(), map(), timeout()) ::
          {:ok, Jason.Encoder.value()} | {:error, error()}
  def command(driver, method, params \\ %{}, timeout \\ @command_timeout)
      when is_binary(method) and is_map(params) do
    GenServer.call(driver, {:command, method, params}, timeout)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    owner = Keyword.get(opts, :owner, self())
    driver_path = opts |> Keyword.fetch!(:driver_path) |> Path.expand()
    node_path = Keyword.get_lazy(opts, :node_path, &find_node!/0)
    env = opts |> Keyword.get(:env, %{}) |> port_env()

    port =
      Port.open(
        {:spawn_executable, node_path},
        [
          :binary,
          :exit_status,
          args: [driver_path],
          env: env,
          line: @max_line_size
        ]
      )

    case await_ready(port) do
      :ok ->
        {:ok, %__MODULE__{owner: owner, port: port}}

      {:error, reason} ->
        close_port(port)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:command, method, params}, from, state) do
    id = state.next_id + 1
    payload = Jason.encode_to_iodata!(%{id: id, method: method, params: params})
    true = Port.command(state.port, [payload, ?\n])

    {:noreply, %{state | next_id: id, pending: Map.put(state.pending, id, from)}}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buffer: state.buffer <> chunk}}
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    message = state.buffer <> line
    {:noreply, state |> Map.put(:buffer, "") |> handle_driver_message(message)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    error = %{
      "code" => "driver_exit",
      "message" => "Playtest Node driver exited with status #{status}",
      "status" => status
    }

    Logger.error(
      "Playtest Node driver failed during sidecar execution: exit_status=#{status} " <>
        "error_code=driver_exit"
    )

    Enum.each(state.pending, fn {_id, from} -> GenServer.reply(from, {:error, error}) end)
    {:stop, {:driver_exit, status}, %{state | pending: %{}}}
  end

  @impl true
  def terminate(_reason, state) do
    shutdown_driver(state.port, state.buffer, state.owner)
    close_port(state.port)
    :ok
  end

  ## Private functions

  defp await_ready(port) do
    receive do
      {^port, {:data, {:eol, line}}} -> decode_ready(line)
      {^port, {:exit_status, status}} -> {:error, {:driver_exit, status}}
    after
      @ready_timeout -> {:error, :driver_ready_timeout}
    end
  end

  defp decode_ready(line) do
    case Jason.decode(line) do
      {:ok, %{"event" => "driver.ready", "params" => %{"protocol" => @protocol_version}}} ->
        :ok

      {:ok, %{"event" => "driver.ready", "params" => %{"protocol" => version}}} ->
        {:error, {:unsupported_protocol, version}}

      {:ok, %{"event" => "driver.fatal", "params" => params}} ->
        {:error, {:driver_fatal, params}}

      {:ok, message} ->
        {:error, {:invalid_ready_message, message}}

      {:error, error} ->
        {:error, {:invalid_ready_json, Exception.message(error)}}
    end
  end

  defp handle_driver_message(state, message) do
    case Jason.decode(message) do
      {:ok, %{"id" => id, "result" => result}} ->
        reply_to_pending(state, id, {:ok, result})

      {:ok, %{"id" => id, "error" => error}} ->
        reply_to_pending(state, id, {:error, error})

      {:ok, %{"event" => event, "params" => params}} ->
        send(state.owner, {:playtest_event, self(), event, params})
        state

      {:ok, decoded} ->
        report_protocol_error(state, "unexpected_message", inspect(decoded))

      {:error, error} ->
        report_protocol_error(state, "invalid_json", Exception.message(error))
    end
  end

  defp reply_to_pending(state, id, response) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        report_protocol_error(state, "unknown_response", "No caller registered for id #{id}")

      {from, pending} ->
        GenServer.reply(from, response)
        %{state | pending: pending}
    end
  end

  defp report_protocol_error(state, code, detail) do
    Logger.error(
      "Playtest Node driver protocol failure while decoding sidecar output: " <>
        "error_code=#{code} detail=#{String.slice(detail, 0, 500)}"
    )

    send(state.owner, {
      :playtest_event,
      self(),
      "driver.protocol_error",
      %{"code" => code, "detail" => detail}
    })

    state
  end

  defp find_node!() do
    System.find_executable("node") ||
      raise "Playtest cannot start its sidecar because the Node.js executable was not found"
  end

  defp shutdown_driver(port, buffer, owner) do
    if Port.info(port) do
      payload = Jason.encode_to_iodata!(%{id: @shutdown_id, method: "driver.close", params: %{}})
      true = Port.command(port, [payload, ?\n])
      deadline = System.monotonic_time(:millisecond) + @shutdown_timeout
      await_shutdown(port, buffer, owner, deadline)
    end
  catch
    :error, :badarg -> :ok
  end

  defp await_shutdown(port, buffer, owner, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        await_shutdown(port, buffer <> chunk, owner, deadline)

      {^port, {:data, {:eol, line}}} ->
        case Jason.decode(buffer <> line) do
          {:ok, %{"id" => @shutdown_id, "result" => true}} ->
            :ok

          {:ok, %{"id" => @shutdown_id, "error" => error}} ->
            Logger.error(
              "Playtest driver rejected browser cleanup during sidecar shutdown: " <>
                "error_code=driver_shutdown_failed cause=#{inspect(error)}"
            )

          {:ok, %{"event" => event, "params" => params}} ->
            send(owner, {:playtest_event, self(), event, params})
            await_shutdown(port, "", owner, deadline)

          _message ->
            await_shutdown(port, "", owner, deadline)
        end

      {^port, {:exit_status, _status}} ->
        :ok
    after
      timeout ->
        Logger.error(
          "Playtest driver did not acknowledge browser cleanup before sidecar shutdown: " <>
            "error_code=driver_shutdown_timeout timeout_ms=#{@shutdown_timeout}"
        )
    end
  end

  defp close_port(nil), do: :ok

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  catch
    :error, :badarg -> :ok
  end

  defp port_env(env) do
    Enum.map(env, fn {name, value} -> {String.to_charlist(name), String.to_charlist(value)} end)
  end
end
