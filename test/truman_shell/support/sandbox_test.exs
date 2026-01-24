defmodule TrumanShell.Support.SandboxTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Support.Sandbox

  describe "sandbox_root/0" do
    test "returns TRUMAN_DOME env var when set" do
      System.put_env("TRUMAN_DOME", "/custom/dome")
      result = Sandbox.sandbox_root()
      assert result == "/custom/dome"
      System.delete_env("TRUMAN_DOME")
    end

    test "returns File.cwd!() when env var is not set" do
      System.delete_env("TRUMAN_DOME")
      result = Sandbox.sandbox_root()
      assert result == File.cwd!()
    end

    test "returns File.cwd!() when env var is empty string" do
      System.put_env("TRUMAN_DOME", "")
      result = Sandbox.sandbox_root()
      assert result == File.cwd!()
      System.delete_env("TRUMAN_DOME")
    end

    test "expands tilde to home directory" do
      System.put_env("TRUMAN_DOME", "~/studios/reification-labs")
      result = Sandbox.sandbox_root()
      home = System.get_env("HOME")
      assert result == Path.join(home, "studios/reification-labs")
      System.delete_env("TRUMAN_DOME")
    end

    test "expands dot to current working directory" do
      System.put_env("TRUMAN_DOME", ".")
      result = Sandbox.sandbox_root()
      assert result == File.cwd!()
      System.delete_env("TRUMAN_DOME")
    end

    test "expands relative path to absolute" do
      System.put_env("TRUMAN_DOME", "./my-project")
      result = Sandbox.sandbox_root()
      assert result == Path.join(File.cwd!(), "my-project")
      System.delete_env("TRUMAN_DOME")
    end

    test "does NOT expand dollar-sign env var references" do
      System.put_env("TRUMAN_DOME", "$HOME/projects")
      result = Sandbox.sandbox_root()
      assert result == "$HOME/projects"
      System.delete_env("TRUMAN_DOME")
    end

    test "normalizes trailing slashes" do
      System.put_env("TRUMAN_DOME", "/custom/dome///")
      result = Sandbox.sandbox_root()
      assert result == "/custom/dome"
      System.delete_env("TRUMAN_DOME")
    end
  end

  describe "build_context/0" do
    test "returns context map with sandbox_root key" do
      context = Sandbox.build_context()
      assert Map.has_key?(context, :sandbox_root)
      assert Map.has_key?(context, :current_dir)
    end

    test "context includes current_dir matching sandbox_root by default" do
      context = Sandbox.build_context()
      assert context.current_dir == context.sandbox_root
    end
  end

  describe "error_message/1" do
    test "outside_sandbox error converts to 'No such file or directory'" do
      message = Sandbox.error_message({:error, :outside_sandbox})
      assert message == "No such file or directory"
    end

    test "enoent error converts to 'No such file or directory'" do
      message = Sandbox.error_message({:error, :enoent})
      assert message == "No such file or directory"
    end
  end

  describe "validate_path/2" do
    @tag :tmp_dir
    test "rejects symlink with absolute target outside sandbox", %{tmp_dir: sandbox} do
      # Create a symlink inside sandbox that points to /tmp (outside sandbox)
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("/tmp", symlink_path)

      # The symlink exists inside sandbox, but points outside
      result = Sandbox.validate_path("escape_link", sandbox)

      # Should be rejected because absolute target escapes sandbox
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows symlink with absolute target inside sandbox", %{tmp_dir: sandbox} do
      # Symlinks with absolute paths inside sandbox ARE allowed
      # We follow the symlink and verify the real path is within bounds
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "abs_link")
      File.ln_s(inside_dir, symlink_path)

      result = Sandbox.validate_path("abs_link", sandbox)

      # Allowed: we follow symlinks and verify real destination
      assert {:ok, ^inside_dir} = result
    end

    @tag :tmp_dir
    test "rejects symlink with relative escaping target", %{tmp_dir: sandbox} do
      # Symlink with relative path that escapes via ..
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("../../etc/passwd", symlink_path)

      result = Sandbox.validate_path("escape_link", sandbox)

      # Rejected: relative target escapes via ..
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows symlink with safe relative target", %{tmp_dir: sandbox} do
      # Create target directory and symlink with relative path
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "safe_link")
      File.ln_s("inside", symlink_path)

      result = Sandbox.validate_path("safe_link", sandbox)

      # Allowed: relative target stays within sandbox
      assert {:ok, _} = result
    end

    test "allows path within sandbox" do
      sandbox = "/tmp/truman-test"
      path = "subdir/file.txt"

      result = Sandbox.validate_path(path, sandbox)

      # Returns resolved path (may include /private/ on macOS)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/truman-test/subdir/file.txt")
    end

    test "rejects path traversal attack" do
      sandbox = "/tmp/truman-test"
      path = "../../../etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects absolute path outside sandbox" do
      # Absolute paths outside sandbox are rejected (AIITL transparency)
      # This is more honest than silently confining /etc -> sandbox/etc
      sandbox = "/tmp/truman-test"
      path = "/etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      # Path is rejected, not confined
      assert {:error, :outside_sandbox} = result
    end

    test "allows absolute path within sandbox" do
      # Absolute paths that are already within sandbox should work
      sandbox = "/tmp/truman-test"
      path = "/tmp/truman-test/subdir/file.txt"

      result = Sandbox.validate_path(path, sandbox)

      # Returns resolved path (may include /private/ on macOS)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/truman-test/subdir/file.txt")
    end

    test "rejects path with sandbox prefix but different directory" do
      # Security: /tmp/truman-test2 should NOT pass for sandbox /tmp/truman-test
      # This catches the string prefix bug where "truman-test2" starts with "truman-test"
      sandbox = "/tmp/truman-test"
      path = "/tmp/truman-test2/secret"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "allows current directory (.)" do
      sandbox = "/tmp/truman-test"
      path = "."

      result = Sandbox.validate_path(path, sandbox)

      # Returns resolved path (may include /private/ on macOS)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/truman-test")
    end
  end

  describe "validate_path/3 with current_dir" do
    setup do
      tmp_dir = System.tmp_dir!()
      sandbox = Path.join(tmp_dir, "test_sandbox_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.mkdir_p!(Path.join(sandbox, "lib"))
      File.write!(Path.join(sandbox, "lib/foo.ex"), "# test file")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    test "resolves relative path within sandbox", %{sandbox: sandbox} do
      relative_path = "lib/foo.ex"
      current_dir = sandbox

      result = Sandbox.validate_path(relative_path, sandbox, current_dir)

      # Returns resolved path - check it ends with expected suffix
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "rejects relative path that escapes via traversal", %{sandbox: sandbox} do
      relative_path = "../../../etc/passwd"
      current_dir = sandbox

      result = Sandbox.validate_path(relative_path, sandbox, current_dir)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects symlink pointing outside sandbox", %{sandbox: sandbox} do
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("/etc", symlink_path)

      result = Sandbox.validate_path(symlink_path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "accepts symlink pointing within sandbox", %{sandbox: sandbox} do
      target = Path.join(sandbox, "lib/foo.ex")
      symlink_path = Path.join(sandbox, "foo_link.ex")
      File.ln_s(target, symlink_path)

      result = Sandbox.validate_path(symlink_path, sandbox)

      # Returns resolved path - should end with same suffix as target
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "rejects path through directory symlink pointing outside sandbox", %{sandbox: sandbox} do
      # SECURITY: This is the intermediate symlink escape attack
      # A directory symlink inside sandbox points outside,
      # then we access files THROUGH that directory
      #
      # Attack scenario:
      #   ln -s /etc /sandbox/escape_dir
      #   validate_path("escape_dir/passwd", "/sandbox")
      #
      # If we only check the final path component, this passes
      # because "passwd" is a regular file, not a symlink

      escape_dir = Path.join(sandbox, "escape_dir")
      File.ln_s("/etc", escape_dir)

      # Try to access a file THROUGH the symlinked directory
      result = Sandbox.validate_path("escape_dir/passwd", sandbox)

      # MUST be rejected - the real path is /etc/passwd
      assert {:error, :outside_sandbox} = result
    end

    test "rejects chained symlinks that escape sandbox", %{sandbox: sandbox} do
      # SECURITY: Chained symlinks can also escape
      # link1 -> link2 -> /etc/passwd

      # Create a file outside sandbox to link to (use /tmp as it's more reliable)
      outside_file = Path.join(System.tmp_dir!(), "outside_target_#{:rand.uniform(100_000)}")
      File.write!(outside_file, "secret")
      on_exit(fn -> File.rm(outside_file) end)

      # Create chain: link1 -> link2 -> outside_file
      link2 = Path.join(sandbox, "link2")
      File.ln_s(outside_file, link2)

      link1 = Path.join(sandbox, "link1")
      File.ln_s(link2, link1)

      result = Sandbox.validate_path("link1", sandbox)

      # MUST be rejected - following the chain leads outside
      assert {:error, :outside_sandbox} = result
    end
  end
end
