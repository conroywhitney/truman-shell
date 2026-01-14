defmodule TrumanShell.Commands.TreeWalkerTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.TreeWalker

  @moduletag :commands

  describe "walk/2" do
    test "walks nested directory structure returning files and directories" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-walker-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create nested structure:
        # tmp_dir/
        #   file1.txt
        #   subdir/
        #     file2.txt
        #     nested/
        #       file3.txt
        File.mkdir_p!(Path.join([tmp_dir, "subdir", "nested"]))
        File.write!(Path.join(tmp_dir, "file1.txt"), "")
        File.write!(Path.join([tmp_dir, "subdir", "file2.txt"]), "")
        File.write!(Path.join([tmp_dir, "subdir", "nested", "file3.txt"]), "")

        entries = TreeWalker.walk(tmp_dir)

        # Should return list of {path, type} tuples
        paths = Enum.map(entries, fn {path, _type} -> Path.basename(path) end)
        types = Map.new(entries, fn {path, type} -> {Path.basename(path), type} end)

        assert "file1.txt" in paths
        assert "file2.txt" in paths
        assert "file3.txt" in paths
        assert "subdir" in paths
        assert "nested" in paths

        # Verify types
        assert types["file1.txt"] == :file
        assert types["subdir"] == :dir
        assert types["nested"] == :dir
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "respects maxdepth option to limit traversal" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-walker-depth-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create 3 levels deep:
        # tmp_dir/
        #   level0.txt          (depth 0 - immediate child)
        #   a/                  (depth 0)
        #     level1.txt        (depth 1)
        #     b/                (depth 1)
        #       level2.txt      (depth 2)
        File.mkdir_p!(Path.join([tmp_dir, "a", "b"]))
        File.write!(Path.join(tmp_dir, "level0.txt"), "")
        File.write!(Path.join([tmp_dir, "a", "level1.txt"]), "")
        File.write!(Path.join([tmp_dir, "a", "b", "level2.txt"]), "")

        # maxdepth: 1 = only immediate children (depth 0)
        entries = TreeWalker.walk(tmp_dir, maxdepth: 1)
        paths = Enum.map(entries, fn {path, _} -> Path.basename(path) end)

        assert "level0.txt" in paths
        assert "a" in paths
        refute "level1.txt" in paths
        refute "b" in paths
        refute "level2.txt" in paths

        # maxdepth: 2 = children and grandchildren (depth 0-1)
        entries2 = TreeWalker.walk(tmp_dir, maxdepth: 2)
        paths2 = Enum.map(entries2, fn {path, _} -> Path.basename(path) end)

        assert "level0.txt" in paths2
        assert "a" in paths2
        assert "level1.txt" in paths2
        assert "b" in paths2
        refute "level2.txt" in paths2
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "filters by type: :file to return only files" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-walker-type-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join([tmp_dir, "subdir", "nested"]))
        File.write!(Path.join(tmp_dir, "file1.txt"), "")
        File.write!(Path.join([tmp_dir, "subdir", "file2.txt"]), "")

        entries = TreeWalker.walk(tmp_dir, type: :file)
        paths = Enum.map(entries, fn {path, _} -> Path.basename(path) end)
        types = Enum.map(entries, fn {_, type} -> type end) |> Enum.uniq()

        # Should only have files
        assert "file1.txt" in paths
        assert "file2.txt" in paths
        refute "subdir" in paths
        refute "nested" in paths

        # All entries should be :file type
        assert types == [:file]
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "filters by type: :dir to return only directories" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-walker-type-dir-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join([tmp_dir, "subdir", "nested"]))
        File.write!(Path.join(tmp_dir, "file1.txt"), "")

        entries = TreeWalker.walk(tmp_dir, type: :dir)
        paths = Enum.map(entries, fn {path, _} -> Path.basename(path) end)
        types = Enum.map(entries, fn {_, type} -> type end) |> Enum.uniq()

        # Should only have directories
        assert "subdir" in paths
        assert "nested" in paths
        refute "file1.txt" in paths

        # All entries should be :dir type
        assert types == [:dir]
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
