defmodule TrumanShell.Commands.MkdirTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Mkdir
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "mkdir_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      ctx = %Context{current_path: sandbox, sandbox_config: config}
      {:ok, ctx: ctx, sandbox: sandbox}
    end

    test "creates a new directory", %{ctx: ctx, sandbox: sandbox} do
      result = Mkdir.handle(["newdir"], ctx)

      assert {:ok, ""} = result
      assert File.dir?(Path.join(sandbox, "newdir"))
    end

    test "returns error when directory already exists", %{ctx: ctx, sandbox: sandbox} do
      # Create the directory first
      existing = Path.join(sandbox, "existing")
      File.mkdir!(existing)

      result = Mkdir.handle(["existing"], ctx)

      assert {:error, "mkdir: existing: File exists\n"} = result
    end

    test "blocks mkdir outside sandbox (404 principle)", %{ctx: ctx} do
      # Attempting to create /etc/hacked should return "No such file" not "Permission denied"
      result = Mkdir.handle(["/etc/hacked"], ctx)

      assert {:error, "mkdir: /etc/hacked: No such file or directory\n"} = result
    end

    test "mkdir -p creates parent directories", %{ctx: ctx, sandbox: sandbox} do
      result = Mkdir.handle(["-p", "path/to/nested"], ctx)

      assert {:ok, ""} = result
      assert File.dir?(Path.join(sandbox, "path/to/nested"))
    end

    test "mkdir -p succeeds even if directory exists", %{ctx: ctx, sandbox: sandbox} do
      # Create the directory first
      existing = Path.join(sandbox, "already_exists")
      File.mkdir!(existing)

      result = Mkdir.handle(["-p", "already_exists"], ctx)

      assert {:ok, ""} = result
    end
  end
end
