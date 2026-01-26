defmodule TrumanShell.Commands.WhichTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Which
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  defp build_ctx do
    config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
    %Context{current_path: "/sandbox", sandbox_config: config}
  end

  describe "handle/2" do
    test "returns builtin info for known command" do
      ctx = build_ctx()

      {:ok, output} = Which.handle(["ls"], ctx)

      assert output == "ls: TrumanShell builtin\n"
    end

    test "returns error for unknown command" do
      ctx = build_ctx()

      {:error, output} = Which.handle(["notreal"], ctx)

      assert output == "notreal not found\n"
    end

    test "handles multiple commands with one unknown" do
      ctx = build_ctx()

      # Returns error if ANY command is not found (for chaining like `which cmd && ...`)
      {:error, output} = Which.handle(["ls", "cat", "fake"], ctx)

      assert output == "ls: TrumanShell builtin\ncat: TrumanShell builtin\nfake not found\n"
    end

    test "returns ok when all commands found" do
      ctx = build_ctx()

      {:ok, output} = Which.handle(["ls", "cat"], ctx)

      assert output == "ls: TrumanShell builtin\ncat: TrumanShell builtin\n"
    end

    test "returns error with no arguments" do
      ctx = build_ctx()

      {:error, output} = Which.handle([], ctx)

      assert output =~ "usage:"
    end
  end
end
