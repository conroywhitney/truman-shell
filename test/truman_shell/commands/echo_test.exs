defmodule TrumanShell.Commands.EchoTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Echo

  @moduletag :commands

  describe "handle/2" do
    test "returns single argument with newline" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "hello\n"} = Echo.handle(["hello"], context)
    end

    test "joins multiple arguments with spaces" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "hello world\n"} = Echo.handle(["hello", "world"], context)
    end

    test "returns just newline with no arguments" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "\n"} = Echo.handle([], context)
    end

    test "echo -n omits trailing newline" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "hello"} = Echo.handle(["-n", "hello"], context)
    end

    test "echo -n with multiple arguments" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      assert {:ok, "hello world"} = Echo.handle(["-n", "hello", "world"], context)
    end
  end
end
