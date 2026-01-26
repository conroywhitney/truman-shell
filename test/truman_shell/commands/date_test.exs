defmodule TrumanShell.Commands.DateTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Date, as: DateCmd
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  defp build_ctx do
    config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
    %Context{current_path: "/sandbox", sandbox_config: config}
  end

  describe "handle/2" do
    test "returns current date and time" do
      ctx = build_ctx()

      {:ok, output} = DateCmd.handle([], ctx)

      # Should match format like "Thu Jan 16 10:30:45 UTC 2026"
      # Day Mon DD HH:MM:SS TZ YYYY (day is space-padded: " 9" not "09")
      assert output =~ ~r/^\w{3} \w{3} [ \d]\d \d{2}:\d{2}:\d{2} \w+ \d{4}\n$/
    end

    test "ignores arguments" do
      ctx = build_ctx()

      {:ok, output} = DateCmd.handle(["ignored", "args"], ctx)

      assert output =~ ~r/^\w{3} \w{3} [ \d]\d \d{2}:\d{2}:\d{2} \w+ \d{4}\n$/
    end
  end
end
