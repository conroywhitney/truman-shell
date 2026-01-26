defmodule TrumanShell.Commands.EchoTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Echo
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  defp build_ctx do
    config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
    %Context{current_path: "/sandbox", sandbox_config: config}
  end

  describe "handle/2" do
    test "returns single argument with newline" do
      ctx = build_ctx()

      assert {:ok, "hello\n"} = Echo.handle(["hello"], ctx)
    end

    test "joins multiple arguments with spaces" do
      ctx = build_ctx()

      assert {:ok, "hello world\n"} = Echo.handle(["hello", "world"], ctx)
    end

    test "returns just newline with no arguments" do
      ctx = build_ctx()

      assert {:ok, "\n"} = Echo.handle([], ctx)
    end

    test "echo -n omits trailing newline" do
      ctx = build_ctx()

      assert {:ok, "hello"} = Echo.handle(["-n", "hello"], ctx)
    end

    test "echo -n with multiple arguments" do
      ctx = build_ctx()

      assert {:ok, "hello world"} = Echo.handle(["-n", "hello", "world"], ctx)
    end
  end
end
