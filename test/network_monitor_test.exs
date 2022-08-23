defmodule NetworkMonitorTest do
  use ExUnit.Case
  doctest NetworkMonitor

  test "greets the world" do
    assert NetworkMonitor.hello() == :world
  end
end
