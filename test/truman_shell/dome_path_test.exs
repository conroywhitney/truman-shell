defmodule TrumanShell.DomePathTest do
  @moduledoc """
  Tests for DomePath - THE path module for TrumanShell.

  DomePath is the ONLY module that should use Path.* directly.
  All other modules go through DomePath for path operations.

  **Core functions:**
  - `validate/3` - expand + boundary check + symlink detection
  - `within?/2` - pure string boundary checking

  **Wrapper functions (delegate to Path.*):**
  - `basename/1`, `dirname/1`, `type/1`, `split/1`
  - `join/1`, `join/2`
  - `expand/1`, `expand/2`
  - `relative_to/2`
  - `wildcard/1`, `wildcard/2`

  **Symlinks are denied.** Any symlink = `{:error, :symlink}`.
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

    test "rejects /etc path (symlink on macOS, outside_boundary on Linux)", %{sandbox: sandbox} do
      # /etc is a symlink to /private/etc on macOS, but a real dir on Linux
      result = DomePath.validate("/etc/passwd", sandbox)

      case :os.type() do
        {:unix, :darwin} -> assert {:error, :symlink} = result
        {:unix, :linux} -> assert {:error, :outside_boundary} = result
        _ -> assert {:error, _} = result
      end
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
  # Wrapper functions - delegate to Path.* (DomePath is the ONLY Path.* user)
  # =============================================================================

  describe "basename/1" do
    test "returns filename from path" do
      assert DomePath.basename("/foo/bar/baz.ex") == "baz.ex"
    end

    test "returns directory name for directory path" do
      assert DomePath.basename("/foo/bar/") == "bar"
    end

    test "handles root path" do
      assert DomePath.basename("/") == ""
    end
  end

  describe "type/1" do
    test "returns :absolute for absolute path" do
      assert DomePath.type("/foo/bar") == :absolute
    end

    test "returns :relative for relative path" do
      assert DomePath.type("foo/bar") == :relative
    end

    test "returns :relative for dot path" do
      assert DomePath.type("./foo") == :relative
    end
  end

  describe "dirname/1" do
    test "returns parent directory of file path" do
      assert DomePath.dirname("/foo/bar/baz.ex") == "/foo/bar"
    end

    test "returns parent of nested directory" do
      assert DomePath.dirname("/foo/bar") == "/foo"
    end

    test "returns root for top-level file" do
      assert DomePath.dirname("/foo") == "/"
    end

    test "returns dot for relative file without directory" do
      assert DomePath.dirname("foo.ex") == "."
    end
  end

  describe "split/1" do
    test "splits absolute path into components" do
      assert DomePath.split("/foo/bar/baz") == ["/", "foo", "bar", "baz"]
    end

    test "splits relative path into components" do
      assert DomePath.split("foo/bar/baz") == ["foo", "bar", "baz"]
    end

    test "handles single component" do
      assert DomePath.split("foo") == ["foo"]
    end
  end

  describe "join/2" do
    test "joins two path segments" do
      assert DomePath.join("/foo", "bar") == "/foo/bar"
    end

    test "handles trailing slash in first segment" do
      assert DomePath.join("/foo/", "bar") == "/foo/bar"
    end

    test "second absolute path is appended (Elixir behavior)" do
      # Note: Elixir Path.join does NOT replace first path with absolute second
      # This differs from some other languages
      assert DomePath.join("/foo", "/bar") == "/foo/bar"
    end
  end

  describe "join/1" do
    test "joins list of path segments" do
      assert DomePath.join(["/foo", "bar", "baz"]) == "/foo/bar/baz"
    end

    test "handles empty list gracefully" do
      # Path.join/1 crashes on empty list, but DomePath handles it
      assert DomePath.join([]) == ""
    end

    test "handles single element list" do
      assert DomePath.join(["foo"]) == "foo"
    end
  end

  describe "expand/1" do
    test "expands relative path to absolute" do
      result = DomePath.expand("foo")
      assert DomePath.type(result) == :absolute
      assert String.ends_with?(result, "/foo")
    end

    test "expands tilde to home directory" do
      result = DomePath.expand("~")
      assert DomePath.type(result) == :absolute
      assert result == System.user_home!()
    end

    test "returns absolute path unchanged (normalized)" do
      result = DomePath.expand("/foo/bar")
      assert result == "/foo/bar"
    end
  end

  describe "expand/2" do
    test "expands relative path from given base" do
      result = DomePath.expand("bar", "/foo")
      assert result == "/foo/bar"
    end

    test "ignores base for absolute path" do
      result = DomePath.expand("/absolute", "/ignored")
      assert result == "/absolute"
    end

    test "resolves .. in path" do
      result = DomePath.expand("../baz", "/foo/bar")
      assert result == "/foo/baz"
    end
  end

  describe "relative_to/2" do
    test "computes relative path from base" do
      assert DomePath.relative_to("/foo/bar/baz", "/foo") == "bar/baz"
    end

    test "returns path unchanged if not under base" do
      assert DomePath.relative_to("/other/path", "/foo") == "/other/path"
    end

    test "returns dot for same path" do
      assert DomePath.relative_to("/foo", "/foo") == "."
    end
  end

  describe "wildcard/1" do
    setup do
      cwd = File.cwd!()
      sandbox = DomePath.join(cwd, ".test_wildcard_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.write!(DomePath.join(sandbox, "a.txt"), "a")
      File.write!(DomePath.join(sandbox, "b.txt"), "b")
      File.mkdir_p!(DomePath.join(sandbox, "subdir"))
      File.write!(DomePath.join(sandbox, "subdir/c.txt"), "c")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    test "matches files with pattern", %{sandbox: sandbox} do
      pattern = DomePath.join(sandbox, "*.txt")
      result = DomePath.wildcard(pattern)

      assert length(result) == 2
      assert Enum.all?(result, &String.ends_with?(&1, ".txt"))
    end

    test "returns empty list for no matches", %{sandbox: sandbox} do
      pattern = DomePath.join(sandbox, "*.xyz")
      assert DomePath.wildcard(pattern) == []
    end
  end

  describe "wildcard/2" do
    setup do
      cwd = File.cwd!()
      sandbox = DomePath.join(cwd, ".test_wildcard2_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      File.write!(DomePath.join(sandbox, ".hidden"), "hidden")
      File.write!(DomePath.join(sandbox, "visible.txt"), "visible")

      on_exit(fn -> File.rm_rf!(sandbox) end)

      %{sandbox: sandbox}
    end

    test "match_dot: true includes dotfiles", %{sandbox: sandbox} do
      pattern = DomePath.join(sandbox, "*")
      result = DomePath.wildcard(pattern, match_dot: true)

      filenames = Enum.map(result, &DomePath.basename/1)
      assert ".hidden" in filenames
      assert "visible.txt" in filenames
    end

    test "match_dot: false excludes dotfiles", %{sandbox: sandbox} do
      pattern = DomePath.join(sandbox, "*")
      result = DomePath.wildcard(pattern, match_dot: false)

      filenames = Enum.map(result, &DomePath.basename/1)
      refute ".hidden" in filenames
      assert "visible.txt" in filenames
    end
  end
end
