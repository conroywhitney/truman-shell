defmodule TrumanShell.Commands.TrueTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.True, as: TrueCmd
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  defp build_ctx do
    config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
    %Context{current_path: "/sandbox", sandbox_config: config}
  end

  describe "handle/2" do
    test "returns success with empty output" do
      ctx = build_ctx()

      result = TrueCmd.handle([], ctx)

      assert result == {:ok, ""}
    end

    test "ignores arguments" do
      ctx = build_ctx()

      result = TrueCmd.handle(["ignored", "args"], ctx)

      assert result == {:ok, ""}
    end
  end
end
