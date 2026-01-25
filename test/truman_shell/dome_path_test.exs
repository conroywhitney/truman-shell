defmodule TrumanShell.DomePathTest do
  @moduledoc """
  Tests for DomePath - bounded path operations.

  DomePath is the primitive layer for path operations. It provides:
  - `within?/2` - pure string boundary checking (no filesystem access)
  - `validate/3` - expand + boundary check + symlink detection
  - `expand/3` - bounded path expansion
  - `join/3` - bounded path joining
  - `relative/2` - safe relative path computation

  **Symlinks are denied by default.** If any path component is a symlink,
  `validate/3` returns `{:error, :symlink}`. Use config allow_list to
  whitelist known-good symlinks (resolved at config load time).

  Support.Sandbox uses DomePath for the actual path math, then adds
  policy (404 principle, context building, etc.).
  """
  use ExUnit.Case, async: false

  alias TrumanShell.DomePath

  # =============================================================================
  # within?/2 - Pure string boundary check (no filesystem access)
  # =============================================================================

  describe "within?/2" do
    test "returns true for path equal to root" do
      assert DomePath.within?("/sandbox", "/sandbox") == true
    end

    test "returns true for path inside root" do
      assert DomePath.within?("/sandbox/lib/foo.ex", "/sandbox") == true
    end

    test "returns false for path outside root" do
      assert DomePath.within?("/etc/passwd", "/sandbox") == false
    end

    test "returns false for path with similar prefix but different directory" do
      # Security: /sandbox2 should NOT be within /sandbox
      assert DomePath.within?("/sandbox2/file", "/sandbox") == false
    end

    test "returns false for parent directory" do
      assert DomePath.within?("/", "/sandbox") == false
    end

    test "handles paths with trailing slash correctly" do
      assert DomePath.within?("/sandbox/file", "/sandbox") == true
      assert DomePath.within?("/sandbox/file", "/sandbox/") == true
    end

    test "handles deeply nested paths" do
      assert DomePath.within?("/sandbox/a/b/c/d/e/f.txt", "/sandbox") == true
    end

    test "empty path component edge case" do
      # Double slashes should not affect boundary check
      assert DomePath.within?("/sandbox//file", "/sandbox") == true
    end
  end

  # =============================================================================
  # validate/3 - The workhorse: expand + boundary + symlink check
  # =============================================================================

  describe "validate/3" do
    setup do
      # Use a local temp directory to avoid macOS symlinks in /var/folders
      # File.cwd!() returns the real path without symlinks
      cwd = File.cwd!()
      sandbox = Path.join(cwd, ".test_sandbox_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.mkdir_p!(Path.join(sandbox, "lib"))
      File.write!(Path.join(sandbox, "lib/foo.ex"), "# test")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    # --- Basic path validation ---

    test "allows relative path within sandbox", %{sandbox: sandbox} do
      result = DomePath.validate("lib/foo.ex", sandbox)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "allows absolute path within sandbox", %{sandbox: sandbox} do
      path = Path.join(sandbox, "lib/foo.ex")
      result = DomePath.validate(path, sandbox)
      # Returns canonical path (may differ from input on macOS due to /var -> /private/var)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "allows current directory (.)", %{sandbox: sandbox} do
      result = DomePath.validate(".", sandbox)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, Path.basename(sandbox))
    end

    test "rejects absolute path outside sandbox (not symlink)", %{sandbox: sandbox} do
      # Use /Users which exists and isn't a symlink on macOS
      result = DomePath.validate("/Users/nonexistent", sandbox)
      assert {:error, :outside_boundary} = result
    end

    test "rejects system symlink path (/etc on macOS)", %{sandbox: sandbox} do
      # /etc is a symlink to /private/etc on macOS
      # We reject symlinks, so this returns :symlink (not :outside_boundary)
      result = DomePath.validate("/etc/passwd", sandbox)
      assert {:error, :symlink} = result
    end

    test "rejects path traversal attack", %{sandbox: sandbox} do
      result = DomePath.validate("../../../etc/passwd", sandbox)
      assert {:error, :outside_boundary} = result
    end

    test "rejects similar prefix but different directory", %{sandbox: sandbox} do
      # e.g., /tmp/dome_test_123 vs /tmp/dome_test_1234
      sibling = sandbox <> "4/secret"
      result = DomePath.validate(sibling, sandbox)
      assert {:error, :outside_boundary} = result
    end

    # --- Symlink detection (denied by default) ---

    test "rejects symlink pointing outside sandbox", %{sandbox: sandbox} do
      symlink = Path.join(sandbox, "escape_link")
      File.ln_s("/etc", symlink)

      result = DomePath.validate("escape_link", sandbox)
      assert {:error, :symlink} = result
    end

    test "rejects symlink pointing inside sandbox", %{sandbox: sandbox} do
      # Even symlinks to safe targets are rejected (simplifies security model)
      target = Path.join(sandbox, "lib")
      symlink = Path.join(sandbox, "lib_link")
      File.ln_s(target, symlink)

      result = DomePath.validate("lib_link", sandbox)
      assert {:error, :symlink} = result
    end

    test "rejects intermediate directory symlink", %{sandbox: sandbox} do
      # SECURITY: This is the intermediate symlink escape attack
      # ln -s /etc sandbox/escape_dir; validate("escape_dir/passwd")
      escape_dir = Path.join(sandbox, "escape_dir")
      File.ln_s("/etc", escape_dir)

      result = DomePath.validate("escape_dir/passwd", sandbox)
      assert {:error, :symlink} = result
    end

    test "rejects chained symlinks", %{sandbox: sandbox} do
      # link1 -> link2 -> target
      target = Path.join(sandbox, "target")
      File.write!(target, "content")

      link2 = Path.join(sandbox, "link2")
      File.ln_s(target, link2)

      link1 = Path.join(sandbox, "link1")
      File.ln_s(link2, link1)

      result = DomePath.validate("link1", sandbox)
      assert {:error, :symlink} = result
    end

    test "allows regular files (not symlinks)", %{sandbox: sandbox} do
      result = DomePath.validate("lib/foo.ex", sandbox)
      assert {:ok, _} = result
    end

    test "allows regular directories (not symlinks)", %{sandbox: sandbox} do
      result = DomePath.validate("lib", sandbox)
      assert {:ok, _} = result
    end

    # --- $VAR rejection ---

    test "rejects path with embedded $VAR", %{sandbox: sandbox} do
      result = DomePath.validate("safe/$HOME/escape", sandbox)
      assert {:error, :embedded_var} = result
    end

    test "rejects path starting with $VAR", %{sandbox: sandbox} do
      result = DomePath.validate("$HOME/escape", sandbox)
      assert {:error, :embedded_var} = result
    end

    # --- current_dir parameter ---

    test "resolves relative path from current_dir", %{sandbox: sandbox} do
      current_dir = Path.join(sandbox, "lib")
      result = DomePath.validate("foo.ex", sandbox, current_dir)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/lib/foo.ex")
    end

    test "rejects current_dir outside sandbox", %{sandbox: sandbox} do
      # Use /Users which exists and isn't a symlink on macOS
      result = DomePath.validate("file.txt", sandbox, "/Users")
      assert {:error, :outside_boundary} = result
    end

    test "rejects current_dir with embedded $VAR", %{sandbox: sandbox} do
      current_dir = Path.join(sandbox, "$HOME/subdir")
      result = DomePath.validate("file.txt", sandbox, current_dir)
      assert {:error, :embedded_var} = result
    end

    test "rejects symlink as current_dir", %{sandbox: sandbox} do
      # If current_dir is a symlink, reject it
      real_dir = Path.join(sandbox, "real_dir")
      File.mkdir_p!(real_dir)

      link_dir = Path.join(sandbox, "link_dir")
      File.ln_s(real_dir, link_dir)

      result = DomePath.validate("file.txt", sandbox, link_dir)
      assert {:error, :symlink} = result
    end

    # --- Non-existent paths ---

    test "allows non-existent path within sandbox", %{sandbox: sandbox} do
      # For create operations (touch, mkdir), path may not exist yet
      result = DomePath.validate("new_file.txt", sandbox)
      assert {:ok, resolved} = result
      assert String.ends_with?(resolved, "/new_file.txt")
    end

    test "rejects non-existent path outside sandbox", %{sandbox: sandbox} do
      result = DomePath.validate("/nonexistent/file.txt", sandbox)
      assert {:error, :outside_boundary} = result
    end
  end

  # =============================================================================
  # expand/3 - Bounded path expansion
  # =============================================================================

  describe "expand/3" do
    @tag :skip
    test "expands tilde to home directory within boundary" do
      # Future work
    end

    @tag :skip
    test "rejects tilde expansion that escapes boundary" do
      # Future work
    end
  end

  # =============================================================================
  # join/3 - Bounded path joining
  # =============================================================================

  describe "join/3" do
    @tag :skip
    test "joins paths within boundary" do
      # Future work
    end

    @tag :skip
    test "rejects join that would escape boundary" do
      # Future work
    end
  end

  # =============================================================================
  # relative/2 - Safe relative path computation
  # =============================================================================

  describe "relative/2" do
    @tag :skip
    test "computes relative path within boundary" do
      # Future work
    end

    @tag :skip
    test "rejects relative computation for path outside boundary" do
      # Future work
    end
  end
end
