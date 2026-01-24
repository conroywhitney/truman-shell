defmodule TrumanShell.BoundariesTest do
  @moduledoc """
  TDD tests for TrumanShell.Boundaries module.

  These tests are written BEFORE implementation (red phase).
  Run with: mix test test/truman_shell/boundaries_test.exs
  """
  use ExUnit.Case, async: true

  alias TrumanShell.Boundaries

  describe "playground_root/0" do
    test "returns TRUMAN_PLAYGROUND_ROOT env var when set" do
      # GIVEN the env var is set
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "/custom/playground")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN it returns the env var value
      assert result == "/custom/playground"

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "returns File.cwd!() when env var is not set" do
      # GIVEN the env var is not set
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN it returns the current working directory
      assert result == File.cwd!()
    end

    test "returns File.cwd!() when env var is empty string" do
      # GIVEN the env var is empty
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN it falls back to cwd
      assert result == File.cwd!()

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "expands tilde to home directory" do
      # GIVEN the env var uses tilde notation
      # (shell may not expand if set via config file)
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "~/studios/reification-labs")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN tilde is expanded to $HOME
      home = System.get_env("HOME")
      assert result == Path.join(home, "studios/reification-labs")

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "expands dot to current working directory" do
      # GIVEN the env var is '.'
      System.put_env("TRUMAN_PLAYGROUND_ROOT", ".")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN it resolves to cwd (absolute path)
      assert result == File.cwd!()

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "expands relative path to absolute" do
      # GIVEN the env var is a relative path
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "./my-project")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN it resolves to absolute path from cwd
      assert result == Path.join(File.cwd!(), "my-project")

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "does NOT expand dollar-sign env var references" do
      # GIVEN the env var contains a literal $VAR reference
      # (we don't expand these - that's the shell's job, and a security risk)
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "$HOME/projects")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN the literal string is returned (not expanded)
      # This is intentional - we don't eval arbitrary env var references
      assert result == "$HOME/projects"

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end

    test "normalizes trailing slashes" do
      # GIVEN the env var has trailing slashes
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "/custom/playground///")

      # WHEN getting the playground root
      result = Boundaries.playground_root()

      # THEN trailing slashes are removed
      assert result == "/custom/playground"

      # Cleanup
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
    end
  end

  describe "validate_path/2" do
    setup do
      # Use a temp directory as playground root for isolation
      tmp_dir = System.tmp_dir!()
      playground = Path.join(tmp_dir, "test_playground_#{:rand.uniform(100_000)}")
      File.mkdir_p!(playground)
      File.mkdir_p!(Path.join(playground, "lib"))
      File.write!(Path.join(playground, "lib/foo.ex"), "# test file")

      on_exit(fn -> File.rm_rf!(playground) end)

      %{playground: playground}
    end

    test "accepts path within playground", %{playground: playground} do
      # GIVEN a path inside the playground
      path = Path.join(playground, "lib/foo.ex")

      # WHEN validating
      result = Boundaries.validate_path(path, playground)

      # THEN it returns ok with the absolute path
      assert {:ok, ^path} = result
    end

    test "rejects absolute path outside playground", %{playground: playground} do
      # GIVEN a path outside the playground
      path = "/etc/passwd"

      # WHEN validating
      result = Boundaries.validate_path(path, playground)

      # THEN it returns error
      assert {:error, :outside_playground} = result
    end

    test "rejects path traversal attack", %{playground: playground} do
      # GIVEN a path that uses traversal to escape
      path = Path.join(playground, "../../../etc/passwd")

      # WHEN validating
      result = Boundaries.validate_path(path, playground)

      # THEN it returns error (path is expanded before check)
      assert {:error, :outside_playground} = result
    end

    test "resolves relative path within playground", %{playground: playground} do
      # GIVEN a relative path
      relative_path = "lib/foo.ex"
      current_dir = playground

      # WHEN validating with current_dir context
      result = Boundaries.validate_path(relative_path, playground, current_dir)

      # THEN it returns ok with absolute path
      expected = Path.join(playground, "lib/foo.ex")
      assert {:ok, ^expected} = result
    end

    test "rejects relative path that escapes via traversal", %{playground: playground} do
      # GIVEN a relative path that escapes
      relative_path = "../../../etc/passwd"
      current_dir = playground

      # WHEN validating
      result = Boundaries.validate_path(relative_path, playground, current_dir)

      # THEN it returns error
      assert {:error, :outside_playground} = result
    end

    test "rejects symlink pointing outside playground", %{playground: playground} do
      # GIVEN a symlink inside playground pointing outside
      symlink_path = Path.join(playground, "escape_link")
      File.ln_s("/etc", symlink_path)

      # WHEN validating the symlink target
      result = Boundaries.validate_path(symlink_path, playground)

      # THEN it returns error (realpath is checked)
      assert {:error, :outside_playground} = result
    end

    test "accepts symlink pointing within playground", %{playground: playground} do
      # GIVEN a symlink inside playground pointing to another playground path
      target = Path.join(playground, "lib/foo.ex")
      symlink_path = Path.join(playground, "foo_link.ex")
      File.ln_s(target, symlink_path)

      # WHEN validating
      result = Boundaries.validate_path(symlink_path, playground)

      # THEN it returns ok with the resolved path
      assert {:ok, resolved} = result
      assert resolved == target
    end
  end

  describe "build_context/0" do
    test "returns context map with playground_root key" do
      # GIVEN no specific setup (uses env or cwd)

      # WHEN building context
      context = Boundaries.build_context()

      # THEN it has playground_root
      assert Map.has_key?(context, :playground_root)
      # Also has sandbox_root for backwards compatibility (transition period)
      assert Map.has_key?(context, :sandbox_root)
      assert context.playground_root == context.sandbox_root
    end

    test "context includes current_dir matching playground_root by default" do
      # GIVEN default setup

      # WHEN building context
      context = Boundaries.build_context()

      # THEN current_dir equals playground_root
      assert context.current_dir == context.playground_root
    end
  end

  describe "404 principle - error messages" do
    test "outside_playground error converts to 'No such file or directory'" do
      # GIVEN an outside_playground error
      error = {:error, :outside_playground}

      # WHEN converting to user-facing message
      message = Boundaries.error_message(error)

      # THEN it shows "No such file or directory" (no information leakage)
      assert message == "No such file or directory"
    end
  end
end
