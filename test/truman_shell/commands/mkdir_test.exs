defmodule TrumanShell.Commands.MkdirTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Mkdir

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "mkdir_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      context = %{sandbox_root: sandbox, current_dir: sandbox}
      {:ok, context: context, sandbox: sandbox}
    end

    test "creates a new directory", %{context: context, sandbox: sandbox} do
      result = Mkdir.handle(["newdir"], context)

      assert {:ok, ""} = result
      assert File.dir?(Path.join(sandbox, "newdir"))
    end

    test "returns error when directory already exists", %{context: context, sandbox: sandbox} do
      # Create the directory first
      existing = Path.join(sandbox, "existing")
      File.mkdir!(existing)

      result = Mkdir.handle(["existing"], context)

      assert {:error, "mkdir: existing: File exists\n"} = result
    end

    test "blocks mkdir outside sandbox (404 principle)", %{context: context} do
      # Attempting to create /etc/hacked should return "No such file" not "Permission denied"
      result = Mkdir.handle(["/etc/hacked"], context)

      assert {:error, "mkdir: /etc/hacked: No such file or directory\n"} = result
    end

    test "mkdir -p creates parent directories", %{context: context, sandbox: sandbox} do
      result = Mkdir.handle(["-p", "path/to/nested"], context)

      assert {:ok, ""} = result
      assert File.dir?(Path.join(sandbox, "path/to/nested"))
    end

    test "mkdir -p succeeds even if directory exists", %{context: context, sandbox: sandbox} do
      # Create the directory first
      existing = Path.join(sandbox, "already_exists")
      File.mkdir!(existing)

      result = Mkdir.handle(["-p", "already_exists"], context)

      assert {:ok, ""} = result
    end
  end
end
