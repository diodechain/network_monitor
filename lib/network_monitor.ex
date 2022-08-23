defmodule NetworkMonitor do
  @moduledoc """
  [NetworkMonitor](https://github.com/diodechain/network_monitor) watches network interfaces and emits events to listeners when interfaces appear or vanish.

  # Example

  ```
  {:ok, port} = :gen_tcp.connect('www.google.com', 80)
  NetworkMonitor.close_on_down(port)
  # now when the network cable is unplugged the port
  # is automatically closed
  ```
  """
  use Application
  use GenServer

  @app :network_monitor
  @enforce_keys [:intervall, :timer, :interfaces, :subscribers, :on_down]
  defstruct [:intervall, :timer, :interfaces, :subscribers, :on_down]

  @impl true
  def start(:normal, _opts) do
    intervall = Application.get_env(@app, :intervall, 5_000)

    GenServer.start_link(
      __MODULE__,
      %NetworkMonitor{
        timer: nil,
        intervall: intervall,
        interfaces: interfaces(),
        subscribers: MapSet.new(),
        on_down: %{}
      },
      hibernate_after: 5_000,
      name: __MODULE__
    )
  end

  @impl true
  def init(state = %NetworkMonitor{intervall: intervall}) do
    {:ok, timer} = :timer.send_interval(intervall, :check)
    {:ok, %NetworkMonitor{state | timer: timer}}
  end

  @doc """
  Subscribe to interface events. The given `pid` or `self()` by default
  will receive these two signals on interface changes:

  - `{:interface_down, [ifs]}`
  - `{:interface_up, [ifs]}`

  Where `ifs` is a list of ip address tuples. So for example:
  `{192, 168, 0, 1}` for IPv4 or `{0, 0, 0, 0, 0, 0, 0, 1}` for IPv6
  """
  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Wrapper around `on_down_apply` executes the `:inet.close(socket)` function
  call on the given socket when the sockets associated local interface
  goes down.

  The sockets associated local interface is retrieved using
  `:inet.sockname(socket)`
  """
  def close_on_down(socket) do
    with {:ok, {addr, _ip}} <- :inet.sockname(socket) do
      on_down_apply(addr, :inet, :close, socket)
    end
  end

  @doc """
  Execute the given `{module, function, arguments}` (mfa) tuple when the ip-address
  given in with `addr` is going down. `addr` should be a member of
  `interfaces()` or the mfa will be executed immediately.
  """
  def on_down_apply(addr, m, f, a) when is_atom(m) and is_atom(f) do
    GenServer.call(__MODULE__, {:on_down_apply, addr, {m, f, List.wrap(a)}})
  end

  @impl true
  def handle_call(
        {:on_down_apply, addr, mfa},
        _from,
        state = %NetworkMonitor{on_down: on_down, interfaces: interfaces}
      ) do
    if Map.has_key?(interfaces, addr) do
      on_down =
        Map.update(on_down, addr, MapSet.new([mfa]), fn on_downs ->
          MapSet.put(on_downs, mfa)
        end)

      {:reply, :ok, %NetworkMonitor{state | on_down: on_down}}
    else
      exec_mfa(addr, mfa)
      {:reply, :ok, state}
    end
  end

  defp exec_mfa(_addr, {m, f, a}) do
    spawn(m, f, a)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid}, state = %NetworkMonitor{subscribers: subscribers}) do
    subscribers = MapSet.delete(subscribers, pid)
    {:noreply, %NetworkMonitor{state | subscribers: subscribers}}
  end

  def handle_info(:check, state = %NetworkMonitor{interfaces: old_interfaces, on_down: on_downs}) do
    new_interfaces = interfaces()

    MapSet.difference(old_interfaces, new_interfaces)
    |> MapSet.to_list()
    |> handle_lost_interfaces(state)
    |> Enum.each(fn addr ->
      for mfa <- Map.get(on_downs, addr, []) do
        exec_mfa(addr, mfa)
      end
    end)

    MapSet.difference(new_interfaces, old_interfaces)
    |> MapSet.to_list()
    |> handle_new_interfaces(state)

    {:noreply, %NetworkMonitor{state | interfaces: new_interfaces}}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state = %NetworkMonitor{subscribers: subscribers}) do
    if MapSet.member?(subscribers, pid) do
      {:noreply, state}
    else
      Process.monitor(pid)
      {:noreply, %NetworkMonitor{state | subscribers: MapSet.put(subscribers, pid)}}
    end
  end

  defp handle_lost_interfaces([], _state), do: []

  defp handle_lost_interfaces(lost_interfaces, %NetworkMonitor{subscribers: subs}) do
    for pid <- subs, do: send(pid, {:interface_down, lost_interfaces})
    lost_interfaces
  end

  defp handle_new_interfaces([], _state), do: []

  defp handle_new_interfaces(new_interfaces, %NetworkMonitor{subscribers: subs}) do
    for pid <- subs, do: send(pid, {:interface_up, new_interfaces})
    new_interfaces
  end

  @doc """
  Returns a MapSet of the currently up interfaces
  """
  def interfaces() do
    case :net.getifaddrs() do
      {:ok, ifs} -> ifs
      _ -> []
    end
    |> Enum.filter(fn %{flags: flags} -> Enum.member?(flags, :up) end)
    |> Enum.map(fn %{addr: %{addr: addr}} -> addr end)
    |> MapSet.new()
  end
end
