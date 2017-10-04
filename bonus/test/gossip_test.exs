defmodule GSPTest do
  use ExUnit.Case
  doctest GSP

  test "greets the world" do
    assert GSP.hello() == :world
  end
end
