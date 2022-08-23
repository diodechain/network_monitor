defmodule NetworkMonitorTest do
  use ExUnit.Case
  doctest NetworkMonitor

  test "check interfaces return value" do
    assert is_struct(NetworkMonitor.interfaces(), MapSet)
  end
end
