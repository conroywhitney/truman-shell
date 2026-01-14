defmodule TrumanShell.Commands.EchoTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Echo

  describe "handle/2" do
    test "returns single argument with newline" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "hello\n"} = Echo.handle(["hello"], context)
    end
  end
end
