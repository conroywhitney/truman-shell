defmodule TrumanShell.Support.GlobTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Support.Glob

  @moduletag :support

  # Helper to build ctx
  defp build_ctx(home_path, opts \\ []) do
    current_path = Keyword.get(opts, :current_path, home_path)
    config = %SandboxConfig{allowed_paths: [home_path], home_path: home_path}
    %Context{current_path: current_path, sandbox_config: config}
  end

  # Use a temp directory for filesystem tests
  setup do
    # Create a unique temp directory for each test
    tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "glob_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, home_path: tmp_dir}
  end

  describe "expand/2 with * pattern" do
    test "expands *.md to matching files", %{home_path: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "README.md"), "readme")
      File.write!(Path.join(sandbox, "CHANGELOG.md"), "changelog")
      File.write!(Path.join(sandbox, "other.txt"), "other")

      ctx = build_ctx(sandbox)
      result = Glob.expand("*.md", ctx)

      assert result == ["CHANGELOG.md", "README.md"]
    end
  end

  describe "expand/2 with ** recursive pattern" do
    test "expands **/*.md to files in all subdirectories", %{home_path: sandbox} do
      # Create directory structure
      File.write!(Path.join(sandbox, "README.md"), "root readme")
      File.mkdir_p!(Path.join(sandbox, "docs"))
      File.write!(Path.join([sandbox, "docs", "guide.md"]), "guide")
      File.mkdir_p!(Path.join([sandbox, "docs", "api"]))
      File.write!(Path.join([sandbox, "docs", "api", "ref.md"]), "api ref")

      ctx = build_ctx(sandbox)
      result = Glob.expand("**/*.md", ctx)

      assert result == ["README.md", "docs/api/ref.md", "docs/guide.md"]
    end
  end

  describe "expand/2 sandbox boundary enforcement" do
    test "rejects glob when base path is outside sandbox before expansion", %{home_path: sandbox} do
      # Create a file inside sandbox to prove we're not just failing on no-match
      File.write!(Path.join(sandbox, "exists.md"), "exists")

      ctx = build_ctx(sandbox)

      # Absolute path outside sandbox - base path (/etc) is not in sandbox
      # This should return original pattern WITHOUT calling Path.wildcard
      result = Glob.expand("/etc/*.conf", ctx)
      assert result == "/etc/*.conf"

      # Relative path that escapes - base path (../) resolves outside sandbox
      result = Glob.expand("../../../etc/*.conf", ctx)
      assert result == "../../../etc/*.conf"
    end

    test "expands absolute glob pattern within sandbox", %{home_path: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "file1.md"), "one")
      File.write!(Path.join(sandbox, "file2.md"), "two")

      ctx = build_ctx(sandbox)

      # Absolute path INSIDE sandbox should expand and return absolute paths
      result = Glob.expand("#{sandbox}/*.md", ctx)

      assert is_list(result)
      assert length(result) == 2
      # Results should be absolute paths since pattern was absolute
      assert "#{sandbox}/file1.md" in result
      assert "#{sandbox}/file2.md" in result
    end

    test "glob with ../ parent traversal returns original pattern (no escape)", %{home_path: sandbox} do
      # Create a file in sandbox
      File.write!(Path.join(sandbox, "inside.md"), "inside")

      # Create a file outside sandbox (in parent of sandbox)
      parent_dir = Path.dirname(sandbox)
      outside_file = Path.join(parent_dir, "outside.md")
      File.write!(outside_file, "outside")

      on_exit(fn -> File.rm(outside_file) end)

      ctx = build_ctx(sandbox)

      # Pattern that would match outside files if not constrained
      result = Glob.expand("../*.md", ctx)

      # Should NOT include the outside file - return original pattern (no matches)
      assert result == "../*.md"
    end

    test "filters results to only include files inside sandbox", %{home_path: _sandbox} do
      # Create nested sandbox structure
      outer_dir = Path.join(Path.join(File.cwd!(), "tmp"), "glob_outer_#{:erlang.unique_integer([:positive])}")
      inner_dir = Path.join(outer_dir, "sandbox")
      File.mkdir_p!(inner_dir)

      # File inside sandbox
      File.write!(Path.join(inner_dir, "inside.md"), "inside")

      # File outside sandbox (in parent)
      File.write!(Path.join(outer_dir, "outside.md"), "outside")

      on_exit(fn -> File.rm_rf!(outer_dir) end)

      # Sandbox is inner_dir, current_path is also inner_dir
      ctx = build_ctx(inner_dir)

      # This pattern stays inside sandbox
      result = Glob.expand("*.md", ctx)
      assert result == ["inside.md"]

      # This pattern tries to escape - should return original (no matches in sandbox)
      result = Glob.expand("../*.md", ctx)
      assert result == "../*.md"
    end
  end

  describe "expand/2 no-match behavior" do
    test "returns original pattern when no files match", %{home_path: sandbox} do
      ctx = build_ctx(sandbox)

      result = Glob.expand("*.nonexistent", ctx)

      assert result == "*.nonexistent"
    end

    test "returns original pattern for empty directory glob", %{home_path: sandbox} do
      # Create empty subdirectory
      empty_dir = Path.join(sandbox, "empty_dir")
      File.mkdir_p!(empty_dir)

      ctx = build_ctx(sandbox)

      result = Glob.expand("empty_dir/*.md", ctx)

      assert result == "empty_dir/*.md"
    end
  end

  describe "expand/2 dotfile handling" do
    test "* pattern excludes dotfiles by default", %{home_path: sandbox} do
      # Create regular file and dotfiles
      File.write!(Path.join(sandbox, "file.txt"), "regular")
      File.write!(Path.join(sandbox, ".hidden"), "hidden")
      File.write!(Path.join(sandbox, ".config"), "config")

      ctx = build_ctx(sandbox)

      result = Glob.expand("*", ctx)

      # Should only include regular file, not dotfiles
      assert result == ["file.txt"]
    end

    test ".* pattern matches dotfiles explicitly", %{home_path: sandbox} do
      # Create regular file and dotfiles
      File.write!(Path.join(sandbox, "file.txt"), "regular")
      File.write!(Path.join(sandbox, ".hidden"), "hidden")
      File.write!(Path.join(sandbox, ".config"), "config")

      ctx = build_ctx(sandbox)

      result = Glob.expand(".*", ctx)

      # Should only include dotfiles, sorted
      assert result == [".config", ".hidden"]
    end

    test ".config/* pattern matches files in dotdir", %{home_path: sandbox} do
      # Create dotdir with files
      config_dir = Path.join(sandbox, ".config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(config_dir, "settings.json"), "settings")
      File.write!(Path.join(config_dir, "cache.db"), "cache")

      ctx = build_ctx(sandbox)

      result = Glob.expand(".config/*", ctx)

      # Should match files in the .config directory
      assert result == [".config/cache.db", ".config/settings.json"]
    end

    test "*/*.txt does NOT match files in dotdirs (bash compat)", %{home_path: sandbox} do
      # Create visible dir and dotdir with files
      File.mkdir_p!(Path.join(sandbox, "visible"))
      File.write!(Path.join([sandbox, "visible", "file.txt"]), "visible")
      File.mkdir_p!(Path.join(sandbox, ".hidden"))
      File.write!(Path.join([sandbox, ".hidden", "file.txt"]), "hidden")

      ctx = build_ctx(sandbox)

      result = Glob.expand("*/*.txt", ctx)

      # Should only match visible/file.txt, not .hidden/file.txt
      assert result == ["visible/file.txt"]
    end
  end

  describe "expand/2 multiple wildcards" do
    test "matches pattern with multiple underscores *_*_test.exs", %{home_path: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "foo_bar_test.exs"), "")
      File.write!(Path.join(sandbox, "a_b_test.exs"), "")
      File.write!(Path.join(sandbox, "single_test.exs"), "")

      ctx = build_ctx(sandbox)

      result = Glob.expand("*_*_test.exs", ctx)

      # Only matches files with 2+ underscores before _test.exs
      assert result == ["a_b_test.exs", "foo_bar_test.exs"]
    end

    test "matches wildcards in both name and extension f*o.*d", %{home_path: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "foo.md"), "")
      File.write!(Path.join(sandbox, "filo.txt"), "")
      File.write!(Path.join(sandbox, "franco.bad"), "")

      ctx = build_ctx(sandbox)

      result = Glob.expand("f*o.*d", ctx)

      # filo.txt excluded - extension doesn't end with 'd'
      assert result == ["foo.md", "franco.bad"]
    end
  end

  describe "expand/2 depth limit" do
    test "depth limit works correctly with absolute glob patterns", %{home_path: sandbox} do
      # Create a structure 5 levels deep
      deep_path = Path.join([sandbox, "a", "b", "c", "d", "e"])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "deep.ex"), "deep")
      File.write!(Path.join(sandbox, "root.ex"), "root")

      ctx = build_ctx(sandbox)

      # Absolute pattern with ** - depth should be counted from the base_dir (sandbox)
      result = Glob.expand("#{sandbox}/**/*.ex", ctx)

      assert is_list(result)
      # Both files should be found since 5 levels is under 100 limit
      assert "#{sandbox}/a/b/c/d/e/deep.ex" in result
      assert "#{sandbox}/root.ex" in result
    end

    test "recursive glob includes files within depth limit", %{home_path: sandbox} do
      # Create structure 5 levels deep (well under 100 limit)
      deep_path = Path.join([sandbox, "a", "b", "c", "d", "e"])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "deep.md"), "deep")
      File.write!(Path.join(sandbox, "root.md"), "root")

      ctx = build_ctx(sandbox)

      result = Glob.expand("**/*.md", ctx)

      # Both files should be found (5 levels is under 100 limit)
      assert "a/b/c/d/e/deep.md" in result
      assert "root.md" in result
    end

    test "depth is counted from glob base directory", %{home_path: sandbox} do
      # Create nested structure
      File.mkdir_p!(Path.join([sandbox, "src", "lib", "deep"]))
      File.write!(Path.join([sandbox, "src", "lib", "deep", "file.ex"]), "")
      File.write!(Path.join([sandbox, "src", "root.ex"]), "")

      ctx = build_ctx(sandbox)

      # Glob from src/ - depth counts from there
      result = Glob.expand("src/**/*.ex", ctx)

      assert result == ["src/lib/deep/file.ex", "src/root.ex"]
    end
  end

  describe "expand/2 preserves ./ prefix (bash compatibility)" do
    test "./*.ex preserves ./ prefix in results", %{home_path: sandbox} do
      File.write!(Path.join(sandbox, "a.ex"), "a")
      File.write!(Path.join(sandbox, "b.ex"), "b")

      ctx = build_ctx(sandbox)

      result = Glob.expand("./*.ex", ctx)

      # Bash preserves the ./ prefix
      assert result == ["./a.ex", "./b.ex"]
    end

    test "*.ex without prefix has no prefix in results", %{home_path: sandbox} do
      File.write!(Path.join(sandbox, "x.ex"), "x")

      ctx = build_ctx(sandbox)

      result = Glob.expand("*.ex", ctx)

      assert result == ["x.ex"]
    end
  end

  describe "expand/2 filenames with spaces" do
    test "matches files with spaces in name", %{home_path: sandbox} do
      # Create files with spaces
      File.write!(Path.join(sandbox, "my file.txt"), "content")
      File.write!(Path.join(sandbox, "another file.txt"), "content")
      File.write!(Path.join(sandbox, "nospace.txt"), "content")

      ctx = build_ctx(sandbox)

      result = Glob.expand("*.txt", ctx)

      assert result == ["another file.txt", "my file.txt", "nospace.txt"]
    end

    test "matches files in directory with spaces", %{home_path: sandbox} do
      # Create directory with space
      dir_with_space = Path.join(sandbox, "my dir")
      File.mkdir_p!(dir_with_space)
      File.write!(Path.join(dir_with_space, "file.md"), "content")

      ctx = build_ctx(sandbox)

      result = Glob.expand("my dir/*.md", ctx)

      assert result == ["my dir/file.md"]
    end
  end

  describe "expand/2 symlink security" do
    test "rejects glob when base path IS a symlink", %{home_path: sandbox} do
      # Create a real directory with files
      real_dir = Path.join(sandbox, "real_dir")
      File.mkdir_p!(real_dir)
      File.write!(Path.join(real_dir, "file.md"), "content")

      # Create a symlink to it
      link_path = Path.join(sandbox, "link_to_real")
      File.ln_s!(real_dir, link_path)

      ctx = build_ctx(sandbox)

      # Pattern with symlink in base path should return original pattern
      # because base validation will detect the symlink
      result = Glob.expand("link_to_real/*.md", ctx)

      assert result == "link_to_real/*.md"
    end

    test "rejects glob results that traverse symlinks in subdirectories", %{home_path: sandbox} do
      # Create a directory structure
      parent_dir = Path.join(sandbox, "parent")
      File.mkdir_p!(parent_dir)

      # Create a real file in parent (should be found)
      File.write!(Path.join(parent_dir, "real.md"), "real content")

      # Create a symlink to /etc inside parent
      etc_link = Path.join(parent_dir, "etc_link")
      # Only create if not on a system where /etc doesn't exist
      if File.exists?("/etc") do
        File.ln_s!("/etc", etc_link)

        ctx = build_ctx(sandbox)

        # Pattern: parent/*/*.conf
        # This WOULD match /etc/*.conf if symlinks were followed
        # But the filter should reject symlink paths
        result = Glob.expand("parent/*/*.conf", ctx)

        # Should NOT find any /etc files - either no match or only sandbox files
        assert result == "parent/*/*.conf" or
                 (is_list(result) and not Enum.any?(result, &String.contains?(&1, "etc_link")))
      end
    end

    test "glob results through symlinks are filtered by validation", %{home_path: sandbox} do
      # Create structure: dir/link -> outside
      # Pattern: dir/link/*
      # Path.wildcard would return dir/link/file paths
      # But DomePath.validate should reject them because link is a symlink

      outside_dir = Path.join(Path.dirname(sandbox), "outside_glob_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(outside_dir)
      File.write!(Path.join(outside_dir, "secret.md"), "secret data")

      on_exit(fn -> File.rm_rf!(outside_dir) end)

      # Create a symlink inside sandbox pointing outside
      inside_dir = Path.join(sandbox, "dir")
      File.mkdir_p!(inside_dir)
      link_path = Path.join(inside_dir, "link")
      File.ln_s!(outside_dir, link_path)

      ctx = build_ctx(sandbox)

      # Try to glob through the symlink
      result = Glob.expand("dir/link/*.md", ctx)

      # Should return original pattern (base contains symlink, rejected before wildcard)
      # Per Glob contract: "no match returns original pattern"
      assert result == "dir/link/*.md"
    end
  end

  describe "expand/2 root wildcard patterns (edge cases)" do
    # These tests verify that absolute patterns with wildcards at the root level
    # are rejected BEFORE calling Path.wildcard, preventing filesystem enumeration
    # outside the sandbox. The glob_base_dir/1 function correctly extracts "/"
    # as the base, which fails the in_sandbox? check.

    test "rejects /* pattern (wildcard immediately after root)", %{home_path: sandbox} do
      ctx = build_ctx(sandbox)

      # Base would be "/" which is outside any sandbox
      assert Glob.expand("/*", ctx) == "/*"
    end

    test "rejects /**/* pattern (recursive from root)", %{home_path: sandbox} do
      ctx = build_ctx(sandbox)

      # Base would be "/" - rejected before enumeration
      assert Glob.expand("/**/*", ctx) == "/**/*"
    end

    test "rejects /*/*.conf pattern (nested wildcard from root)", %{home_path: sandbox} do
      ctx = build_ctx(sandbox)

      # Base would be "/" - rejected before enumeration
      assert Glob.expand("/*/*.conf", ctx) == "/*/*.conf"
    end
  end

  describe "expand/2 depth limit enforcement" do
    # The depth limit (100 levels) prevents DoS via deeply nested glob patterns.
    # This test verifies files beyond the limit are actually filtered out.

    test "filters out matches beyond max depth (100 levels)", %{home_path: sandbox} do
      # Build 101 directories deep
      deep_dirs = Enum.map(1..101, fn i -> "d#{i}" end)
      deep_path = Path.join([sandbox | deep_dirs])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "too_deep.md"), "should not appear")

      # File at root level (depth 0)
      File.write!(Path.join(sandbox, "ok.md"), "ok")

      ctx = build_ctx(sandbox)
      result = Glob.expand("**/*.md", ctx)

      assert is_list(result)
      assert "ok.md" in result
      # The file 101 levels deep should be filtered out
      refute Enum.any?(result, &String.contains?(&1, "too_deep.md")),
             "Found too_deep.md - depth limit not enforced!"
    end

    test "includes matches at exactly max depth (100 levels)", %{home_path: sandbox} do
      # Depth is counted as: number of path components from base_dir
      # So 99 directories + 1 filename = depth 100
      deep_dirs = Enum.map(1..99, fn i -> "d#{i}" end)
      deep_path = Path.join([sandbox | deep_dirs])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "at_limit.md"), "should appear")

      ctx = build_ctx(sandbox)
      result = Glob.expand("**/*.md", ctx)

      assert is_list(result)
      # File at exactly depth 100 (99 dirs + filename) should be included
      assert Enum.any?(result, &String.contains?(&1, "at_limit.md")),
             "at_limit.md not found - depth limit too strict!"
    end
  end

  describe "expand/2 current_path validation (defense-in-depth)" do
    # These tests verify that Glob.expand raises for invalid current_path,
    # since Context enforces current_path is set but doesn't validate it's sane.
    # In normal operation, current_path is always validated by the cd command.

    test "raises when current_path is relative" do
      # Can't easily test this because Context struct requires current_path,
      # and our build_ctx helper always builds valid contexts.
      # The ArgumentError is raised inside Glob.expand for relative paths.
      sandbox = File.cwd!()
      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      # Manually construct with relative current_path
      ctx = %Context{current_path: ".", sandbox_config: config}

      assert_raise ArgumentError, ~r/current_path must be absolute/, fn ->
        Glob.expand("*.md", ctx)
      end
    end

    test "raises when current_path is outside sandbox" do
      sandbox = File.cwd!()
      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      ctx = %Context{current_path: "/tmp", sandbox_config: config}

      assert_raise ArgumentError, ~r/current_path must be absolute and inside sandbox/, fn ->
        Glob.expand("*.md", ctx)
      end
    end

    test "raises when current_path contains symlink" do
      sandbox = File.cwd!()
      tmp_dir = Path.join(sandbox, "tmp/glob_symlink_test_#{:erlang.unique_integer([:positive])}")

      # Create a symlink directory
      real_dir = Path.join(tmp_dir, "real")
      File.mkdir_p!(real_dir)

      link_dir = Path.join(tmp_dir, "link")
      File.ln_s!(real_dir, link_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
      ctx = %Context{current_path: link_dir, sandbox_config: config}

      assert_raise ArgumentError, ~r/current_path must be absolute and inside sandbox/, fn ->
        Glob.expand("*.md", ctx)
      end
    end

    test "accepts glob with valid absolute current_path", %{home_path: sandbox} do
      # Create a file
      File.write!(Path.join(sandbox, "valid.md"), "content")

      # Valid context - should work normally
      ctx = build_ctx(sandbox)
      result = Glob.expand("*.md", ctx)

      assert is_list(result)
      assert "valid.md" in result
    end
  end
end
