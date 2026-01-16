defmodule TrumanShell.Commands.TrueTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.True, as: TrueCmd

  @moduletag :commands

  describe "handle/2" do
    test "returns success with empty output" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      result = TrueCmd.handle([], context)

      assert result == {:ok, ""}
    end

    test "ignores arguments" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      result = TrueCmd.handle(["ignored", "args"], context)

      assert result == {:ok, ""}
    end
  end
end
