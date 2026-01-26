defmodule TrumanShell.Commands.FalseTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.False, as: FalseCmd
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  defp build_ctx do
    config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
    %Context{current_path: "/sandbox", sandbox_config: config}
  end

  describe "handle/2" do
    test "returns error with empty message" do
      ctx = build_ctx()

      result = FalseCmd.handle([], ctx)

      assert result == {:error, ""}
    end

    test "ignores arguments" do
      ctx = build_ctx()

      result = FalseCmd.handle(["ignored", "args"], ctx)

      assert result == {:error, ""}
    end
  end
end
