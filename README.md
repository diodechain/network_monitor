# NetworkMonitor

[NetworkMonitor](https://github.com/diodechain/network_monitor) watches network interfaces and emits events to listeners when interfaces appear or vanish.

## Watch interfaces example

This will print a short messages on the console every time when a network interfaces is coming up or going down:

```elixir
dump = fn dump -> 
  receive do
    {:interface_down, ifs} -> IO.puts("interfaces went down #{inspect ifs}")
    {:interface_up, ifs} -> IO.puts("interfaces came up #{inspect ifs}")
  end
  dump.(dump)
end
spawn(fn -> 
  NetworkMonitor.subscribe()
  dump.(dump) 
end)
```


## Disconnect socket example

```elixir
{:ok, port} = :gen_tcp.connect('www.google.com', 80)
NetworkMonitor.close_on_down(port)
# now when the network cable is unplugged the port
# is automatically closed
```

## Installation

The package can be installed
by adding `network_monitor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:network_monitor, "~> 1.0.0"}
  ]
end
```

The docs can be found at <https://hexdocs.pm/network_monitor>.

