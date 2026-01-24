defmodule TrumanShell.Support.SandboxTest do
  # async: false because sandbox_root/0 tests mutate TRUMAN_DOME env var
  use ExUnit.Case, async: false

  alias TrumanShell.Support.Sandbox

  # Save and restore TRUMAN_DOME around tests that mutate it
  setup do
    original_dome = System.get_env("TRUMAN_DOME")
    on_exit(fn -> restore_env("TRUMAN_DOME", original_dome) end)
    :ok
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  describe "sandbox_root/0" do
    test "returns TRUMAN_DOME env var when set" do
      System.put_env("TRUMAN_DOME", "/custom/dome")
      result = Sandbox.sandbox_root()
      assert result == "/custom/dome"
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
    end

    test "expands tilde to home directory" do
      System.put_env("TRUMAN_DOME", "~/studios/reification-labs")
      result = Sandbox.sandbox_root()
      home = System.get_env("HOME")
      assert result == Path.join(home, "studios/reification-labs")
    end

    test "expands dot to current working directory" do
      System.put_env("TRUMAN_DOME", ".")
      result = Sandbox.sandbox_root()
      assert result == File.cwd!()
    end

    test "expands relative path to absolute" do
      System.put_env("TRUMAN_DOME", "./my-project")
      result = Sandbox.sandbox_root()
      assert result == Path.join(File.cwd!(), "my-project")
    end

    test "does NOT expand dollar-sign env var references" do
      System.put_env("TRUMAN_DOME", "$HOME/projects")
      result = Sandbox.sandbox_root()
      assert result == "$HOME/projects"
    end

    test "normalizes trailing slashes" do
      System.put_env("TRUMAN_DOME", "/custom/dome///")
      result = Sandbox.sandbox_root()
      assert result == "/custom/dome"
    end

    # Note: TRUMAN_DOME existence validation deferred to future PR
    # Current behavior: returns the configured path even if it doesn't exist
    # This allows testing with mock paths while production should use real dirs
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

    test "eloop error converts to 'Too many levels of symbolic links'" do
      message = Sandbox.error_message({:error, :eloop})
      assert message == "Too many levels of symbolic links"
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

    test "returns :eloop for self-referential symlinks", %{sandbox: sandbox} do
      # SECURITY: Symlink that points to itself creates infinite loop
      loop_link = Path.join(sandbox, "loop")
      File.ln_s("loop", loop_link)

      result = Sandbox.validate_path("loop", sandbox)

      # Should return :eloop, not hang forever
      assert {:error, :eloop} = result
    end

    test "returns :eloop for deeply nested symlink chains", %{sandbox: sandbox} do
      # SECURITY: Very deep symlink chains should be rejected
      # Create a chain of 15 symlinks (exceeds @max_symlink_depth of 10)
      # link15 -> link14 -> ... -> link1 -> target
      target = Path.join(sandbox, "target")
      File.write!(target, "content")

      # Use Enum.reduce to build the chain properly
      Enum.reduce(1..15, "target", fn i, prev_name ->
        link = Path.join(sandbox, "link#{i}")
        File.ln_s(prev_name, link)
        "link#{i}"
      end)

      result = Sandbox.validate_path("link15", sandbox)

      # Should return :eloop after hitting depth limit
      assert {:error, :eloop} = result
    end

    test "tracks depth correctly when symlink target contains nested symlinks", %{sandbox: sandbox} do
      # SECURITY: Depth must be tracked across nested symlink resolution
      # Bug: resolve_symlink_target passes same depth to both do_resolve_path AND
      # continue_after_symlink, so depth consumed inside do_resolve_path is lost.
      #
      # Setup: entry -> chain of 5 symlinks, then 5 more symlinks in remaining path
      # Total = 1 (entry) + 5 (chain) + 5 (rem) = 11 > 10, should return :eloop
      #
      # Bug scenario:
      # - entry uses 1 depth (10->9)
      # - chain5 resolution: starts at 9, uses 5 internally (9->4), returns success
      # - continue_after_symlink gets depth=9 (not 4!)
      # - rem5 chain uses 5 (9->4 with bug, should be 4->-1 = fail)
      # Result with bug: succeeds! Result correct: :eloop

      # Create target directory structure
      chain_dir = Path.join(sandbox, "chain")
      File.mkdir_p!(chain_dir)

      final_dir = Path.join(chain_dir, "final")
      File.mkdir_p!(final_dir)

      # Create chain inside chain_dir: chain5 -> chain4 -> ... -> chain1 -> final (5 hops)
      Enum.reduce(1..5, "final", fn i, prev ->
        link = Path.join(chain_dir, "chain#{i}")
        File.ln_s(prev, link)
        "chain#{i}"
      end)

      # Create entry symlink that points to chain5 (resolving it internally uses 5 depth)
      entry_link = Path.join(sandbox, "entry")
      File.ln_s(Path.join(chain_dir, "chain5"), entry_link)

      # Create 5 remaining symlinks in final dir: rem5 -> rem4 -> ... -> rem1 -> target
      File.write!(Path.join(final_dir, "target"), "content")

      Enum.reduce(1..5, "target", fn i, prev ->
        link = Path.join(final_dir, "rem#{i}")
        File.ln_s(prev, link)
        "rem#{i}"
      end)

      # Total depth: entry(1) + chain5->final(5) + rem5->target(5) = 11 > 10
      result = Sandbox.validate_path("entry/rem5", sandbox)

      # Should return :eloop - total depth exceeds limit of 10
      assert {:error, :eloop} = result
    end

    test "rejects path with embedded $VAR", %{sandbox: sandbox} do
      # SECURITY: Embedded env var references could escape
      # e.g., /sandbox/safe/$HOME/escape -> /sandbox/safe//Users/me/escape
      path = "safe/$HOME/escape"

      result = Sandbox.validate_path(path, sandbox)

      # Should be rejected - embedded $VAR is not allowed
      assert {:error, :outside_sandbox} = result
    end

    test "rejects current_dir outside sandbox", %{sandbox: sandbox} do
      # SECURITY: If caller passes current_dir outside sandbox,
      # relative paths should still be validated
      outside_dir = "/tmp"
      relative_path = "passwd"

      result = Sandbox.validate_path(relative_path, sandbox, outside_dir)

      # Should be rejected - current_dir is outside sandbox
      assert {:error, :outside_sandbox} = result
    end

    test "allows current_dir inside sandbox", %{sandbox: sandbox} do
      subdir = Path.join(sandbox, "lib")
      File.mkdir_p!(subdir)
      relative_path = "foo.ex"

      result = Sandbox.validate_path(relative_path, sandbox, subdir)

      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "uses resolved current_dir for path resolution", %{sandbox: sandbox} do
      # When current_dir is a symlink, the resolved path should use the canonical form
      # Create: sandbox/link_dir -> sandbox/real_dir
      real_dir = Path.join(sandbox, "real_dir")
      File.mkdir_p!(real_dir)
      File.write!(Path.join(real_dir, "file.txt"), "content")

      link_dir = Path.join(sandbox, "link_dir")
      File.ln_s(real_dir, link_dir)

      # Pass symlink as current_dir, resolve relative path
      result = Sandbox.validate_path("file.txt", sandbox, link_dir)

      # Result should use the canonical path (real_dir), not the symlink path
      assert {:ok, resolved} = result
      assert String.contains?(resolved, "real_dir/file.txt")
      refute String.contains?(resolved, "link_dir")
    end

    test "rejects current_dir with embedded $VAR", %{sandbox: sandbox} do
      # SECURITY: If current_dir contains $VAR, it could be exploited
      # e.g., current_dir = "/sandbox/$HOME" could expand unexpectedly
      path = "file.txt"
      current_dir = Path.join(sandbox, "$HOME/subdir")

      result = Sandbox.validate_path(path, sandbox, current_dir)

      # Should be rejected - embedded $VAR in current_dir is not allowed
      assert {:error, :outside_sandbox} = result
    end
  end
end
