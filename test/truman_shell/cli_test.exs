defmodule TrumanShell.CLITest do
  use ExUnit.Case, async: false

  @moduletag :cli

  # CLI tests use System.cmd/3 to invoke bin/truman-shell because
  # the CLI module calls System.halt/1, which would kill the test runner.
  # This tests the full integration: bash wrapper → Elixir → Sandbox.

  @truman_shell Path.expand("../../bin/truman-shell", __DIR__)

  setup do
    sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "cli_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(sandbox)
    File.mkdir_p!(Path.join(sandbox, "lib"))
    File.write!(Path.join(sandbox, "lib/example.ex"), "# test file")
    File.write!(Path.join(sandbox, "README.md"), "# readme")

    on_exit(fn -> File.rm_rf!(sandbox) end)

    %{sandbox: sandbox}
  end

  describe "validate-path" do
    test "returns resolved path for file inside sandbox", %{sandbox: sandbox} do
      {output, 0} =
        System.cmd(@truman_shell, ["validate-path", "lib/example.ex"], env: [{"TRUMAN_DOME", sandbox}])

      resolved = String.trim(output)
      # Use ends_with? because macOS resolves /var -> /private/var
      assert String.ends_with?(resolved, "/lib/example.ex")
      assert String.contains?(resolved, Path.basename(sandbox))
    end

    test "returns resolved path for absolute path inside sandbox", %{sandbox: sandbox} do
      abs_path = Path.join(sandbox, "README.md")

      {output, 0} =
        System.cmd(@truman_shell, ["validate-path", abs_path], env: [{"TRUMAN_DOME", sandbox}])

      resolved = String.trim(output)
      assert String.ends_with?(resolved, "/README.md")
      assert String.contains?(resolved, Path.basename(sandbox))
    end

    test "exits 1 for path outside sandbox", %{sandbox: sandbox} do
      {_output, exit_code} =
        System.cmd(@truman_shell, ["validate-path", "/etc/passwd"], env: [{"TRUMAN_DOME", sandbox}])

      assert exit_code == 1
    end

    test "exits 1 for path traversal attack", %{sandbox: sandbox} do
      {_output, exit_code} =
        System.cmd(@truman_shell, ["validate-path", "../../../etc/passwd"], env: [{"TRUMAN_DOME", sandbox}])

      assert exit_code == 1
    end

    test "exits 1 for $VAR injection", %{sandbox: sandbox} do
      {_output, exit_code} =
        System.cmd(@truman_shell, ["validate-path", "$HOME/.ssh/id_rsa"], env: [{"TRUMAN_DOME", sandbox}])

      assert exit_code == 1
    end

    test "validates with current_dir argument", %{sandbox: sandbox} do
      lib_dir = Path.join(sandbox, "lib")

      {output, 0} =
        System.cmd(@truman_shell, ["validate-path", "example.ex", lib_dir], env: [{"TRUMAN_DOME", sandbox}])

      resolved = String.trim(output)
      assert String.ends_with?(resolved, "/lib/example.ex")
      assert String.contains?(resolved, Path.basename(sandbox))
    end

    test "exits 1 when no path provided", %{sandbox: sandbox} do
      {output, exit_code} =
        System.cmd(@truman_shell, ["validate-path"],
          env: [{"TRUMAN_DOME", sandbox}],
          stderr_to_stdout: true
        )

      assert exit_code == 1
      assert output =~ "No path provided"
    end
  end

  describe "execute" do
    test "executes a simple command", %{sandbox: sandbox} do
      {output, 0} =
        System.cmd(@truman_shell, ["execute", "echo hello"], env: [{"TRUMAN_DOME", sandbox}])

      assert String.trim(output) == "hello"
    end

    test "blocks commands outside sandbox", %{sandbox: sandbox} do
      {_output, exit_code} =
        System.cmd(@truman_shell, ["execute", "cat /etc/passwd"], env: [{"TRUMAN_DOME", sandbox}])

      assert exit_code == 1
    end
  end

  describe "usage" do
    test "shows usage with --help" do
      {output, _exit_code} =
        System.cmd(@truman_shell, ["--help"], stderr_to_stdout: true)

      assert output =~ "validate-path"
      assert output =~ "execute"
    end
  end
end
