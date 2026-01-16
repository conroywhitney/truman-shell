defmodule TrumanShell.Commands.WhichTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Which

  @moduletag :commands

  describe "handle/2" do
    test "returns builtin info for known command" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = Which.handle(["ls"], context)

      assert output == "ls: TrumanShell builtin\n"
    end

    test "returns not found for unknown command" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = Which.handle(["notreal"], context)

      assert output == "notreal not found\n"
    end

    test "handles multiple commands" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = Which.handle(["ls", "cat", "fake"], context)

      assert output == "ls: TrumanShell builtin\ncat: TrumanShell builtin\nfake not found\n"
    end

    test "returns error with no arguments" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:error, output} = Which.handle([], context)

      assert output =~ "usage:"
    end
  end
end
