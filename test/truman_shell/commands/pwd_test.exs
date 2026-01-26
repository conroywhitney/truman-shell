defmodule TrumanShell.Commands.PwdTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Pwd
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    test "returns current directory with trailing newline" do
      config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      ctx = %Context{current_path: "/sandbox/project", sandbox_config: config}

      {:ok, output} = Pwd.handle([], ctx)

      assert output == "/sandbox/project\n"
    end

    test "ignores any arguments" do
      config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      ctx = %Context{current_path: "/sandbox", sandbox_config: config}

      {:ok, output} = Pwd.handle(["ignored", "args"], ctx)

      assert output == "/sandbox\n"
    end
  end
end
