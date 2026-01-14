defmodule TrumanShell.Commands.PwdTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Pwd

  @moduletag :commands

  describe "handle/2" do
    test "returns current directory with trailing newline" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox/project"}

      {:ok, output} = Pwd.handle([], context)

      assert output == "/sandbox/project\n"
    end

    test "ignores any arguments" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = Pwd.handle(["ignored", "args"], context)

      assert output == "/sandbox\n"
    end
  end
end
