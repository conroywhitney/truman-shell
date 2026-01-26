defmodule TrumanShell.Support.SandboxTest do
  # async: false because dome_root/0 tests mutate TRUMAN_DOME env var
  use ExUnit.Case, async: false

  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Support.Sandbox

  # Save and restore TRUMAN_DOME around tests that mutate it
  setup do
    original_dome = System.get_env("TRUMAN_DOME")
    on_exit(fn -> restore_env("TRUMAN_DOME", original_dome) end)
    :ok
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  describe "dome_root/0" do
    test "returns TRUMAN_DOME env var when set" do
      System.put_env("TRUMAN_DOME", "/custom/dome")
      result = Sandbox.dome_root()
      assert result == "/custom/dome"
    end

    test "returns File.cwd!() when env var is not set" do
      System.delete_env("TRUMAN_DOME")
      result = Sandbox.dome_root()
      assert result == File.cwd!()
    end

    test "returns File.cwd!() when env var is empty string" do
      System.put_env("TRUMAN_DOME", "")
      result = Sandbox.dome_root()
      assert result == File.cwd!()
    end

    test "expands tilde to home directory" do
      System.put_env("TRUMAN_DOME", "~/studios/reification-labs")
      result = Sandbox.dome_root()
      home = System.get_env("HOME")
      assert result == Path.join(home, "studios/reification-labs")
    end

    test "expands dot to current working directory" do
      System.put_env("TRUMAN_DOME", ".")
      result = Sandbox.dome_root()
      assert result == File.cwd!()
    end

    test "expands relative path to absolute" do
      System.put_env("TRUMAN_DOME", "./my-project")
      result = Sandbox.dome_root()
      assert result == Path.join(File.cwd!(), "my-project")
    end

    test "does NOT expand dollar-sign env var references" do
      System.put_env("TRUMAN_DOME", "$HOME/projects")
      result = Sandbox.dome_root()
      assert result == "$HOME/projects"
    end

    test "normalizes trailing slashes" do
      System.put_env("TRUMAN_DOME", "/custom/dome///")
      result = Sandbox.dome_root()
      assert result == "/custom/dome"
    end

    test "normalizes root path to single slash" do
      System.put_env("TRUMAN_DOME", "///")
      result = Sandbox.dome_root()
      assert result == "/"
    end

    # Note: TRUMAN_DOME existence validation deferred to future PR
    # Current behavior: returns the configured path even if it doesn't exist
    # This allows testing with mock paths while production should use real dirs
  end

  # build_context/0 tests removed - deprecated function removed in Phase 3
  # Use build_config/0 instead which returns %Config.Sandbox{}

  describe "build_config/0" do
    test "returns Config.Sandbox struct" do
      config = Sandbox.build_config()
      assert %SandboxConfig{} = config
    end

    test "struct has allowed_paths containing dome_root" do
      config = Sandbox.build_config()
      assert is_list(config.allowed_paths)
      assert length(config.allowed_paths) == 1
      assert Sandbox.dome_root() in config.allowed_paths
    end

    test "struct has home_path set to dome_root" do
      config = Sandbox.build_config()
      assert config.home_path == Sandbox.dome_root()
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

    test "unknown error converts to stringified atom" do
      message = Sandbox.error_message({:error, :some_unknown_error})
      assert message == "some_unknown_error"
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
    test "rejects symlink even with absolute target inside sandbox", %{tmp_dir: sandbox} do
      # Symlinks are DENIED - even if target is inside sandbox
      # "Symlinks denied. Period." - no allow-list, no complexity
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "abs_link")
      File.ln_s(inside_dir, symlink_path)

      result = Sandbox.validate_path("abs_link", sandbox)

      # Rejected: all symlinks denied
      assert {:error, :outside_sandbox} = result
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
    test "rejects symlink even with safe relative target", %{tmp_dir: sandbox} do
      # Symlinks are DENIED - even safe relative targets
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "safe_link")
      File.ln_s("inside", symlink_path)

      result = Sandbox.validate_path("safe_link", sandbox)

      # Rejected: all symlinks denied
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows path within sandbox", %{tmp_dir: sandbox} do
      path = "subdir/file.txt"

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/subdir/file.txt")
    end

    @tag :tmp_dir
    test "rejects path traversal attack", %{tmp_dir: sandbox} do
      path = "../../../etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "rejects absolute path outside sandbox", %{tmp_dir: sandbox} do
      # Absolute paths outside sandbox are rejected (AIITL transparency)
      # This is more honest than silently confining /etc -> sandbox/etc
      path = "/etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      # Path is rejected, not confined
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows absolute path within sandbox", %{tmp_dir: sandbox} do
      # Absolute paths that are already within sandbox should work
      path = Path.join(sandbox, "subdir/file.txt")

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/subdir/file.txt")
    end

    @tag :tmp_dir
    test "rejects path with sandbox prefix but different directory", %{tmp_dir: sandbox} do
      # Security: /sandbox2 should NOT pass for /sandbox
      # This catches the string prefix bug where "sandbox2" starts with "sandbox"
      path = sandbox <> "2/secret"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows current directory (.)", %{tmp_dir: sandbox} do
      path = "."

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, resolved} = result
      assert resolved == sandbox
    end
  end

  describe "validate_path/2 with current_dir via Config.Sandbox" do
    setup do
      # Use project tmp/ to avoid symlinks (macOS /var -> /private/var)
      tmp_dir = Path.join(File.cwd!(), "tmp")
      sandbox = Path.join(tmp_dir, "test_sandbox_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.mkdir_p!(Path.join(sandbox, "lib"))
      File.write!(Path.join(sandbox, "lib/foo.ex"), "# test file")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    test "resolves relative path within sandbox", %{sandbox: sandbox} do
      relative_path = "lib/foo.ex"
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)

      result = Sandbox.validate_path(relative_path, config)

      # Returns resolved path - check it ends with expected suffix
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "rejects relative path that escapes via traversal", %{sandbox: sandbox} do
      relative_path = "../../../etc/passwd"
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)

      result = Sandbox.validate_path(relative_path, config)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects symlink pointing outside sandbox", %{sandbox: sandbox} do
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("/etc", symlink_path)

      result = Sandbox.validate_path(symlink_path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects symlink even pointing within sandbox", %{sandbox: sandbox} do
      # Symlinks are DENIED - even if target is inside sandbox
      target = Path.join(sandbox, "lib/foo.ex")
      symlink_path = Path.join(sandbox, "foo_link.ex")
      File.ln_s(target, symlink_path)

      result = Sandbox.validate_path(symlink_path, sandbox)

      # Rejected: all symlinks denied
      assert {:error, :outside_sandbox} = result
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
      outside_file = Path.join(Path.join(File.cwd!(), "tmp"), "outside_target_#{:rand.uniform(100_000)}")
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

    test "rejects self-referential symlinks", %{sandbox: sandbox} do
      # Symlinks denied - even self-referential ones
      loop_link = Path.join(sandbox, "loop")
      File.ln_s("loop", loop_link)

      result = Sandbox.validate_path("loop", sandbox)

      # Rejected on first symlink detection
      assert {:error, :outside_sandbox} = result
    end

    test "rejects symlink chains", %{sandbox: sandbox} do
      # Symlinks denied - chains rejected on first symlink
      target = Path.join(sandbox, "target")
      File.write!(target, "content")

      # Create a chain: link3 -> link2 -> link1 -> target
      Enum.reduce(1..3, "target", fn i, prev_name ->
        link = Path.join(sandbox, "link#{i}")
        File.ln_s(prev_name, link)
        "link#{i}"
      end)

      result = Sandbox.validate_path("link3", sandbox)

      # Rejected on first symlink (link3)
      assert {:error, :outside_sandbox} = result
    end

    test "rejects path with embedded $VAR", %{sandbox: sandbox} do
      # SECURITY: Embedded env var references could escape
      # e.g., /sandbox/safe/$HOME/escape -> /sandbox/safe//Users/me/escape
      path = "safe/$HOME/escape"

      result = Sandbox.validate_path(path, sandbox)

      # Should be rejected - embedded $VAR is not allowed
      assert {:error, :outside_sandbox} = result
    end

    test "rejects home_path outside sandbox at config creation time", %{sandbox: sandbox} do
      # SECURITY: If caller tries to create config with home_path outside sandbox,
      # SandboxConfig.new/2 rejects it at struct creation time
      outside_dir = "/tmp"

      result = SandboxConfig.new([sandbox], outside_dir)

      # Should be rejected - home_path must be within allowed_paths
      assert {:error, "home_path must be within one of the allowed_paths"} = result
    end

    test "allows current_dir inside sandbox", %{sandbox: sandbox} do
      subdir = Path.join(sandbox, "lib")
      File.mkdir_p!(subdir)
      relative_path = "foo.ex"
      {:ok, config} = SandboxConfig.new([sandbox], subdir)

      result = Sandbox.validate_path(relative_path, config)

      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "rejects symlink as current_dir", %{sandbox: sandbox} do
      # Symlinks are DENIED - even in current_dir
      real_dir = Path.join(sandbox, "real_dir")
      File.mkdir_p!(real_dir)
      File.write!(Path.join(real_dir, "file.txt"), "content")

      link_dir = Path.join(sandbox, "link_dir")
      File.ln_s(real_dir, link_dir)

      # Pass symlink as current_dir
      {:ok, config} = SandboxConfig.new([sandbox], link_dir)
      result = Sandbox.validate_path("file.txt", config)

      # Rejected: symlink in current_dir is not allowed
      assert {:error, :outside_sandbox} = result
    end

    test "rejects current_dir with embedded $VAR", %{sandbox: sandbox} do
      # SECURITY: If current_dir contains $VAR, it could be exploited
      # e.g., current_dir = "/sandbox/$HOME" could expand unexpectedly
      path = "file.txt"
      current_dir = Path.join(sandbox, "$HOME/subdir")
      {:ok, config} = SandboxConfig.new([sandbox], current_dir)

      result = Sandbox.validate_path(path, config)

      # Should be rejected - embedded $VAR in current_dir is not allowed
      assert {:error, :outside_sandbox} = result
    end
  end

  describe "validate_path/2 with Config.Sandbox struct" do
    setup do
      # Use project tmp/ to avoid symlinks (macOS /var -> /private/var)
      tmp_dir = Path.join(File.cwd!(), "tmp")
      sandbox = Path.join(tmp_dir, "test_sandbox_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.mkdir_p!(Path.join(sandbox, "lib"))
      File.write!(Path.join(sandbox, "lib/foo.ex"), "# test file")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    test "validates path within sandbox using Config.Sandbox struct", %{sandbox: sandbox} do
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)
      relative_path = "lib/foo.ex"

      result = Sandbox.validate_path(relative_path, config)

      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end
  end

  describe "validate_path/2 with Context struct" do
    alias TrumanShell.Commands.Context

    setup do
      # Use project tmp/ to avoid symlinks (macOS /var -> /private/var)
      tmp_dir = Path.join(File.cwd!(), "tmp")
      sandbox = Path.join(tmp_dir, "test_sandbox_ctx_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      subdir = Path.join(sandbox, "subdir")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "file.txt"), "content")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox, subdir: subdir}
    end

    test "expands relative path using current_path, not home_path", %{sandbox: sandbox, subdir: subdir} do
      # Key test: current_path differs from home_path
      # Simulates: user cd'd to subdir, then runs `cat file.txt`
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)
      ctx = %Context{current_path: subdir, sandbox_config: config}

      result = Sandbox.validate_path("file.txt", ctx)

      # Should resolve to subdir/file.txt (using current_path), NOT sandbox/file.txt (home_path)
      assert {:ok, resolved} = result
      assert resolved == Path.join(subdir, "file.txt")
    end

    test "rejects path that escapes sandbox via traversal", %{sandbox: sandbox, subdir: subdir} do
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)
      ctx = %Context{current_path: subdir, sandbox_config: config}

      result = Sandbox.validate_path("../../etc/passwd", ctx)

      assert {:error, :outside_sandbox} = result
    end

    test "allows absolute path within sandbox", %{sandbox: sandbox, subdir: subdir} do
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)
      ctx = %Context{current_path: subdir, sandbox_config: config}
      absolute_path = Path.join(sandbox, "subdir/file.txt")

      result = Sandbox.validate_path(absolute_path, ctx)

      assert {:ok, ^absolute_path} = result
    end

    test "rejects absolute path outside sandbox", %{sandbox: sandbox, subdir: subdir} do
      {:ok, config} = SandboxConfig.new([sandbox], sandbox)
      ctx = %Context{current_path: subdir, sandbox_config: config}

      result = Sandbox.validate_path("/etc/passwd", ctx)

      assert {:error, :outside_sandbox} = result
    end
  end
end
