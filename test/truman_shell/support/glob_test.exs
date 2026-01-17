defmodule TrumanShell.Support.GlobTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Support.Glob

  @moduletag :support

  # Use a temp directory for filesystem tests
  setup do
    # Create a unique temp directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "glob_test_#{:erlang.unique_integer([:positive])}")
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

    test "excludes files outside sandbox via parent traversal", %{
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
      outer_dir = Path.join(System.tmp_dir!(), "glob_outer_#{:erlang.unique_integer([:positive])}")
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
end
