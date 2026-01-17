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
end
