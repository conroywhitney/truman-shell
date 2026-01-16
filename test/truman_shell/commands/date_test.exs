defmodule TrumanShell.Commands.DateTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Date, as: DateCmd

  @moduletag :commands

  describe "handle/2" do
    test "returns current date and time" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = DateCmd.handle([], context)

      # Should match format like "Thu Jan 16 10:30:45 EST 2026"
      # Day Mon DD HH:MM:SS TZ YYYY
      assert output =~ ~r/^\w{3} \w{3} \d{1,2} \d{2}:\d{2}:\d{2} \w+ \d{4}\n$/
    end

    test "ignores arguments" do
      context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}

      {:ok, output} = DateCmd.handle(["ignored", "args"], context)

      assert output =~ ~r/^\w{3} \w{3} \d{1,2} \d{2}:\d{2}:\d{2} \w+ \d{4}\n$/
    end
  end
end
