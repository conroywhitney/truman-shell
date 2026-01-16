defmodule TrumanShell.Commands.FalseTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.False, as: FalseCmd

  @moduletag :commands

  describe "handle/2" do
    test "returns error with empty message" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      result = FalseCmd.handle([], context)

      assert result == {:error, ""}
    end

    test "ignores arguments" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      result = FalseCmd.handle(["ignored", "args"], context)

      assert result == {:error, ""}
    end
  end
end
