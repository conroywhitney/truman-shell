defmodule TrumanShell.Support.GlobTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Support.Glob

  @moduletag :support

  # Use a temp directory for filesystem tests
  setup do
    # Create a unique temp directory for each test
    tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "glob_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, sandbox_root: tmp_dir, current_dir: tmp_dir}
  end

  describe "expand/2 with * pattern" do
    test "expands *.md to matching files", %{sandbox_root: sandbox, current_dir: current_dir} do
      # Create test files
      File.write!(Path.join(current_dir, "README.md"), "readme")
      File.write!(Path.join(current_dir, "CHANGELOG.md"), "changelog")
      File.write!(Path.join(current_dir, "other.txt"), "other")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*.md", context)

      assert result == ["CHANGELOG.md", "README.md"]
    end
  end

  describe "expand/2 with ** recursive pattern" do
    test "expands **/*.md to files in all subdirectories", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create directory structure
      File.write!(Path.join(current_dir, "README.md"), "root readme")
      File.mkdir_p!(Path.join(current_dir, "docs"))
      File.write!(Path.join([current_dir, "docs", "guide.md"]), "guide")
      File.mkdir_p!(Path.join([current_dir, "docs", "api"]))
      File.write!(Path.join([current_dir, "docs", "api", "ref.md"]), "api ref")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("**/*.md", context)

      assert result == ["README.md", "docs/api/ref.md", "docs/guide.md"]
    end
  end

  describe "expand/2 sandbox boundary enforcement" do
    test "rejects glob when base path is outside sandbox before expansion", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a file inside sandbox to prove we're not just failing on no-match
      File.write!(Path.join(current_dir, "exists.md"), "exists")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Absolute path outside sandbox - base path (/etc) is not in sandbox
      # This should return original pattern WITHOUT calling Path.wildcard
      result = Glob.expand("/etc/*.conf", context)
      assert result == "/etc/*.conf"

      # Relative path that escapes - base path (../) resolves outside sandbox
      result = Glob.expand("../../../etc/*.conf", context)
      assert result == "../../../etc/*.conf"
    end

    test "expands absolute glob pattern within sandbox", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create test files
      File.write!(Path.join(current_dir, "file1.md"), "one")
      File.write!(Path.join(current_dir, "file2.md"), "two")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Absolute path INSIDE sandbox should expand and return absolute paths
      result = Glob.expand("#{sandbox}/*.md", context)

      assert is_list(result)
      assert length(result) == 2
      # Results should be absolute paths since pattern was absolute
      assert "#{sandbox}/file1.md" in result
      assert "#{sandbox}/file2.md" in result
    end

    test "glob with ../ parent traversal returns original pattern (no escape)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a file in sandbox
      File.write!(Path.join(current_dir, "inside.md"), "inside")

      # Create a file outside sandbox (in parent of sandbox)
      parent_dir = Path.dirname(sandbox)
      outside_file = Path.join(parent_dir, "outside.md")
      File.write!(outside_file, "outside")

      on_exit(fn -> File.rm(outside_file) end)

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Pattern that would match outside files if not constrained
      result = Glob.expand("../*.md", context)

      # Should NOT include the outside file - return original pattern (no matches)
      assert result == "../*.md"
    end

    test "filters results to only include files inside sandbox", %{
      sandbox_root: _sandbox,
      current_dir: _current_dir
    } do
      # Create nested sandbox structure
      outer_dir = Path.join(Path.join(File.cwd!(), "tmp"), "glob_outer_#{:erlang.unique_integer([:positive])}")
      inner_dir = Path.join(outer_dir, "sandbox")
      File.mkdir_p!(inner_dir)

      # File inside sandbox
      File.write!(Path.join(inner_dir, "inside.md"), "inside")

      # File outside sandbox (in parent)
      File.write!(Path.join(outer_dir, "outside.md"), "outside")

      on_exit(fn -> File.rm_rf!(outer_dir) end)

      # Sandbox is inner_dir, current_dir is also inner_dir
      context = %{sandbox_root: inner_dir, current_dir: inner_dir}

      # This pattern stays inside sandbox
      result = Glob.expand("*.md", context)
      assert result == ["inside.md"]

      # This pattern tries to escape - should return original (no matches in sandbox)
      result = Glob.expand("../*.md", context)
      assert result == "../*.md"
    end
  end

  describe "expand/2 no-match behavior" do
    test "returns original pattern when no files match", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # No .nonexistent files exist
      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*.nonexistent", context)

      assert result == "*.nonexistent"
    end

    test "returns original pattern for empty directory glob", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create empty subdirectory
      empty_dir = Path.join(current_dir, "empty_dir")
      File.mkdir_p!(empty_dir)

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("empty_dir/*.md", context)

      assert result == "empty_dir/*.md"
    end
  end

  describe "expand/2 dotfile handling" do
    test "* pattern excludes dotfiles by default", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create regular file and dotfiles
      File.write!(Path.join(current_dir, "file.txt"), "regular")
      File.write!(Path.join(current_dir, ".hidden"), "hidden")
      File.write!(Path.join(current_dir, ".config"), "config")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*", context)

      # Should only include regular file, not dotfiles
      assert result == ["file.txt"]
    end

    test ".* pattern matches dotfiles explicitly", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create regular file and dotfiles
      File.write!(Path.join(current_dir, "file.txt"), "regular")
      File.write!(Path.join(current_dir, ".hidden"), "hidden")
      File.write!(Path.join(current_dir, ".config"), "config")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand(".*", context)

      # Should only include dotfiles, sorted
      assert result == [".config", ".hidden"]
    end

    test ".config/* pattern matches files in dotdir", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create dotdir with files
      config_dir = Path.join(current_dir, ".config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(config_dir, "settings.json"), "settings")
      File.write!(Path.join(config_dir, "cache.db"), "cache")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand(".config/*", context)

      # Should match files in the .config directory
      assert result == [".config/cache.db", ".config/settings.json"]
    end

    test "*/*.txt does NOT match files in dotdirs (bash compat)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create visible dir and dotdir with files
      File.mkdir_p!(Path.join(current_dir, "visible"))
      File.write!(Path.join([current_dir, "visible", "file.txt"]), "visible")
      File.mkdir_p!(Path.join(current_dir, ".hidden"))
      File.write!(Path.join([current_dir, ".hidden", "file.txt"]), "hidden")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*/*.txt", context)

      # Should only match visible/file.txt, not .hidden/file.txt
      assert result == ["visible/file.txt"]
    end
  end

  describe "expand/2 multiple wildcards" do
    test "matches pattern with multiple underscores *_*_test.exs", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create test files
      File.write!(Path.join(current_dir, "foo_bar_test.exs"), "")
      File.write!(Path.join(current_dir, "a_b_test.exs"), "")
      File.write!(Path.join(current_dir, "single_test.exs"), "")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*_*_test.exs", context)

      # Only matches files with 2+ underscores before _test.exs
      assert result == ["a_b_test.exs", "foo_bar_test.exs"]
    end

    test "matches wildcards in both name and extension f*o.*d", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create test files
      File.write!(Path.join(current_dir, "foo.md"), "")
      File.write!(Path.join(current_dir, "filo.txt"), "")
      File.write!(Path.join(current_dir, "franco.bad"), "")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("f*o.*d", context)

      # filo.txt excluded - extension doesn't end with 'd'
      assert result == ["foo.md", "franco.bad"]
    end
  end

  describe "expand/2 depth limit" do
    test "depth limit works correctly with absolute glob patterns", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a structure 5 levels deep
      deep_path = Path.join([current_dir, "a", "b", "c", "d", "e"])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "deep.ex"), "deep")
      File.write!(Path.join(current_dir, "root.ex"), "root")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Absolute pattern with ** - depth should be counted from the base_dir (sandbox)
      result = Glob.expand("#{sandbox}/**/*.ex", context)

      assert is_list(result)
      # Both files should be found since 5 levels is under 100 limit
      assert "#{sandbox}/a/b/c/d/e/deep.ex" in result
      assert "#{sandbox}/root.ex" in result
    end

    test "recursive glob includes files within depth limit", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create structure 5 levels deep (well under 100 limit)
      deep_path = Path.join([current_dir, "a", "b", "c", "d", "e"])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "deep.md"), "deep")
      File.write!(Path.join(current_dir, "root.md"), "root")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("**/*.md", context)

      # Both files should be found (5 levels is under 100 limit)
      assert "a/b/c/d/e/deep.md" in result
      assert "root.md" in result
    end

    test "depth is counted from glob base directory", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create nested structure
      File.mkdir_p!(Path.join([current_dir, "src", "lib", "deep"]))
      File.write!(Path.join([current_dir, "src", "lib", "deep", "file.ex"]), "")
      File.write!(Path.join([current_dir, "src", "root.ex"]), "")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Glob from src/ - depth counts from there
      result = Glob.expand("src/**/*.ex", context)

      assert result == ["src/lib/deep/file.ex", "src/root.ex"]
    end
  end

  describe "expand/2 preserves ./ prefix (bash compatibility)" do
    test "./*.ex preserves ./ prefix in results", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      File.write!(Path.join(current_dir, "a.ex"), "a")
      File.write!(Path.join(current_dir, "b.ex"), "b")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("./*.ex", context)

      # Bash preserves the ./ prefix
      assert result == ["./a.ex", "./b.ex"]
    end

    test "*.ex without prefix has no prefix in results", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      File.write!(Path.join(current_dir, "x.ex"), "x")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*.ex", context)

      assert result == ["x.ex"]
    end
  end

  describe "expand/2 filenames with spaces" do
    test "matches files with spaces in name", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create files with spaces
      File.write!(Path.join(current_dir, "my file.txt"), "content")
      File.write!(Path.join(current_dir, "another file.txt"), "content")
      File.write!(Path.join(current_dir, "nospace.txt"), "content")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("*.txt", context)

      assert result == ["another file.txt", "my file.txt", "nospace.txt"]
    end

    test "matches files in directory with spaces", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create directory with space
      dir_with_space = Path.join(current_dir, "my dir")
      File.mkdir_p!(dir_with_space)
      File.write!(Path.join(dir_with_space, "file.md"), "content")

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      result = Glob.expand("my dir/*.md", context)

      assert result == ["my dir/file.md"]
    end
  end

  describe "expand/2 symlink security" do
    test "rejects glob when base path IS a symlink", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a real directory with files
      real_dir = Path.join(current_dir, "real_dir")
      File.mkdir_p!(real_dir)
      File.write!(Path.join(real_dir, "file.md"), "content")

      # Create a symlink to it
      link_path = Path.join(current_dir, "link_to_real")
      File.ln_s!(real_dir, link_path)

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Pattern with symlink in base path should return original pattern
      # because base validation will detect the symlink
      result = Glob.expand("link_to_real/*.md", context)

      assert result == "link_to_real/*.md"
    end

    test "rejects glob results that traverse symlinks in subdirectories", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a directory structure
      parent_dir = Path.join(current_dir, "parent")
      File.mkdir_p!(parent_dir)

      # Create a real file in parent (should be found)
      File.write!(Path.join(parent_dir, "real.md"), "real content")

      # Create a symlink to /etc inside parent
      etc_link = Path.join(parent_dir, "etc_link")
      # Only create if not on a system where /etc doesn't exist
      if File.exists?("/etc") do
        File.ln_s!("/etc", etc_link)

        context = %{sandbox_root: sandbox, current_dir: current_dir}

        # Pattern: parent/*/*.conf
        # This WOULD match /etc/*.conf if symlinks were followed
        # But the filter should reject symlink paths
        result = Glob.expand("parent/*/*.conf", context)

        # Should NOT find any /etc files - either no match or only sandbox files
        assert result == "parent/*/*.conf" or
                 (is_list(result) and not Enum.any?(result, &String.contains?(&1, "etc_link")))
      end
    end

    test "glob results through symlinks are filtered by validation", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create structure: dir/link -> outside
      # Pattern: dir/link/*
      # Path.wildcard would return dir/link/file paths
      # But DomePath.validate should reject them because link is a symlink

      outside_dir = Path.join(Path.dirname(sandbox), "outside_glob_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(outside_dir)
      File.write!(Path.join(outside_dir, "secret.md"), "secret data")

      on_exit(fn -> File.rm_rf!(outside_dir) end)

      # Create a symlink inside sandbox pointing outside
      inside_dir = Path.join(current_dir, "dir")
      File.mkdir_p!(inside_dir)
      link_path = Path.join(inside_dir, "link")
      File.ln_s!(outside_dir, link_path)

      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Try to glob through the symlink
      result = Glob.expand("dir/link/*.md", context)

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

    test "rejects /* pattern (wildcard immediately after root)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Base would be "/" which is outside any sandbox
      assert Glob.expand("/*", context) == "/*"
    end

    test "rejects /**/* pattern (recursive from root)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Base would be "/" - rejected before enumeration
      assert Glob.expand("/**/*", context) == "/**/*"
    end

    test "rejects /*/*.conf pattern (nested wildcard from root)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      context = %{sandbox_root: sandbox, current_dir: current_dir}

      # Base would be "/" - rejected before enumeration
      assert Glob.expand("/*/*.conf", context) == "/*/*.conf"
    end
  end

  describe "expand/2 depth limit enforcement" do
    # The depth limit (100 levels) prevents DoS via deeply nested glob patterns.
    # This test verifies files beyond the limit are actually filtered out.

    test "filters out matches beyond max depth (100 levels)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Build 101 directories deep
      deep_dirs = Enum.map(1..101, fn i -> "d#{i}" end)
      deep_path = Path.join([current_dir | deep_dirs])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "too_deep.md"), "should not appear")

      # File at root level (depth 0)
      File.write!(Path.join(current_dir, "ok.md"), "ok")

      context = %{sandbox_root: sandbox, current_dir: current_dir}
      result = Glob.expand("**/*.md", context)

      assert is_list(result)
      assert "ok.md" in result
      # The file 101 levels deep should be filtered out
      refute Enum.any?(result, &String.contains?(&1, "too_deep.md")),
             "Found too_deep.md - depth limit not enforced!"
    end

    test "includes matches at exactly max depth (100 levels)", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Depth is counted as: number of path components from base_dir
      # So 99 directories + 1 filename = depth 100
      deep_dirs = Enum.map(1..99, fn i -> "d#{i}" end)
      deep_path = Path.join([current_dir | deep_dirs])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "at_limit.md"), "should appear")

      context = %{sandbox_root: sandbox, current_dir: current_dir}
      result = Glob.expand("**/*.md", context)

      assert is_list(result)
      # File at exactly depth 100 (99 dirs + filename) should be included
      assert Enum.any?(result, &String.contains?(&1, "at_limit.md")),
             "at_limit.md not found - depth limit too strict!"
    end
  end

  describe "expand/2 current_dir validation (defense-in-depth)" do
    # These tests verify that Glob.expand validates current_dir before use,
    # preventing Path.wildcard from resolving against the wrong directory.
    # In normal operation, current_dir is always validated by the cd command,
    # but this provides defense-in-depth against programming errors.

    test "rejects glob when current_dir is relative", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a file so we know matching would work with valid context
      File.write!(Path.join(current_dir, "test.md"), "content")

      # Pass relative current_dir - should fail validation and return pattern
      bad_context = %{sandbox_root: sandbox, current_dir: "."}
      result = Glob.expand("*.md", bad_context)

      # Should return original pattern (failed current_dir validation)
      assert result == "*.md"
    end

    test "rejects glob when current_dir is outside sandbox", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a file so we know matching would work with valid context
      File.write!(Path.join(current_dir, "test.md"), "content")

      # Pass current_dir outside sandbox - should fail validation
      bad_context = %{sandbox_root: sandbox, current_dir: "/tmp"}
      result = Glob.expand("*.md", bad_context)

      # Should return original pattern (failed current_dir validation)
      assert result == "*.md"
    end

    test "rejects glob when current_dir contains symlink", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a symlink directory
      real_dir = Path.join(current_dir, "real")
      File.mkdir_p!(real_dir)
      File.write!(Path.join(real_dir, "test.md"), "content")

      link_dir = Path.join(current_dir, "link")
      File.ln_s!(real_dir, link_dir)

      # Pass symlinked current_dir - should fail validation
      bad_context = %{sandbox_root: sandbox, current_dir: link_dir}
      result = Glob.expand("*.md", bad_context)

      # Should return original pattern (symlink in current_dir)
      assert result == "*.md"
    end

    test "accepts glob with valid absolute current_dir", %{
      sandbox_root: sandbox,
      current_dir: current_dir
    } do
      # Create a file
      File.write!(Path.join(current_dir, "valid.md"), "content")

      # Valid context - should work normally
      good_context = %{sandbox_root: sandbox, current_dir: current_dir}
      result = Glob.expand("*.md", good_context)

      assert is_list(result)
      assert "valid.md" in result
    end
  end
end
