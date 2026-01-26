defmodule TrumanShell.CLITest do
  use ExUnit.Case, async: false

  @moduletag :cli

  # CLI tests use System.cmd/3 to invoke bin/truman-shell because
  # the CLI module calls System.halt/1, which would kill the test runner.
  # This tests the full integration: bash wrapper → Elixir → Sandbox.
  #
  # Note: The CLI uses Config.discover() which defaults to File.cwd!().
  # The bin/truman-shell script cd's to the project root, so all paths
  # are relative to the truman-shell project directory.

  @truman_shell Path.expand("../../bin/truman-shell", __DIR__)

  # Get the project root (where bin/truman-shell cd's to)
  @project_root Path.expand("../..", __DIR__)

  describe "validate-path" do
    test "returns resolved path for file inside sandbox" do
      # lib/truman_shell.ex exists in the project
      {output, 0} = System.cmd(@truman_shell, ["validate-path", "lib/truman_shell.ex"])

      resolved = String.trim(output)
      assert String.ends_with?(resolved, "/lib/truman_shell.ex")
    end

    test "returns resolved path for absolute path inside sandbox" do
      abs_path = Path.join(@project_root, "README.md")

      {output, 0} = System.cmd(@truman_shell, ["validate-path", abs_path])

      resolved = String.trim(output)
      assert String.ends_with?(resolved, "/README.md")
    end

    test "exits 1 for path outside sandbox" do
      {_output, exit_code} = System.cmd(@truman_shell, ["validate-path", "/etc/passwd"])

      assert exit_code == 1
    end

    test "exits 1 for path traversal attack" do
      {_output, exit_code} = System.cmd(@truman_shell, ["validate-path", "../../../etc/passwd"])

      assert exit_code == 1
    end

    test "exits 1 for $VAR injection" do
      {_output, exit_code} = System.cmd(@truman_shell, ["validate-path", "$HOME/.ssh/id_rsa"])

      assert exit_code == 1
    end

    test "shows usage when no path provided" do
      {output, exit_code} =
        System.cmd(@truman_shell, ["validate-path"], stderr_to_stdout: true)

      assert exit_code == 1
      assert output =~ "Usage:"
      assert output =~ "validate-path"
    end
  end

  describe "execute" do
    test "executes a simple command" do
      {output, 0} = System.cmd(@truman_shell, ["execute", "echo hello"])

      assert String.trim(output) == "hello"
    end

    test "blocks commands outside sandbox" do
      {_output, exit_code} = System.cmd(@truman_shell, ["execute", "cat /etc/passwd"])

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
