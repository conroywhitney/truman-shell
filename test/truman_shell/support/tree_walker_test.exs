defmodule TrumanShell.Support.TreeWalkerTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Support.TreeWalker

  @moduletag :support

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
        types = entries |> Enum.map(fn {_, type} -> type end) |> Enum.uniq()

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
        types = entries |> Enum.map(fn {_, type} -> type end) |> Enum.uniq()

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

    test "SECURITY: does not traverse symlinks to directories (prevents sandbox escape)" do
      # Create sandbox directory
      sandbox = Path.join(System.tmp_dir!(), "truman-test-sandbox-#{:rand.uniform(100_000)}")
      # Create outside directory (simulates /etc or other protected area)
      outside = Path.join(System.tmp_dir!(), "truman-test-outside-#{:rand.uniform(100_000)}")

      File.mkdir_p!(sandbox)
      File.mkdir_p!(outside)

      try do
        # Create a "secret" file outside the sandbox
        secret_file = Path.join(outside, "secret.txt")
        File.write!(secret_file, "sensitive data")

        # Create a symlink inside sandbox pointing to outside directory
        escape_link = Path.join(sandbox, "escape")
        File.ln_s!(outside, escape_link)

        # Also create a legitimate file inside sandbox for comparison
        File.write!(Path.join(sandbox, "safe.txt"), "safe content")

        # Walk the sandbox - should NOT traverse through symlink
        entries = TreeWalker.walk(sandbox)
        paths = Enum.map(entries, fn {path, _} -> path end)
        basenames = Enum.map(paths, &Path.basename/1)

        # Should find the safe file
        assert "safe.txt" in basenames

        # Should NOT find the secret file (would indicate sandbox escape)
        refute "secret.txt" in basenames

        # Should NOT list the symlink as a directory or traverse it
        # The symlink itself might appear, but nothing from its target
        refute Enum.any?(paths, fn p -> String.contains?(p, "secret") end)
      after
        File.rm_rf!(sandbox)
        File.rm_rf!(outside)
      end
    end

    test "SECURITY: does not follow symlinks to files" do
      sandbox = Path.join(System.tmp_dir!(), "truman-test-sandbox-file-#{:rand.uniform(100_000)}")
      outside = Path.join(System.tmp_dir!(), "truman-test-outside-file-#{:rand.uniform(100_000)}")

      File.mkdir_p!(sandbox)
      File.mkdir_p!(outside)

      try do
        # Create a secret file outside
        secret_file = Path.join(outside, "secret.txt")
        File.write!(secret_file, "sensitive")

        # Create symlink to that file inside sandbox
        link_to_file = Path.join(sandbox, "linked_secret.txt")
        File.ln_s!(secret_file, link_to_file)

        # Create a real file for comparison
        File.write!(Path.join(sandbox, "real.txt"), "real content")

        entries = TreeWalker.walk(sandbox, type: :file)
        paths = Enum.map(entries, fn {path, _} -> Path.basename(path) end)

        # Should find the real file
        assert "real.txt" in paths

        # Should NOT include symlink as a file (symlinks should be skipped entirely)
        refute "linked_secret.txt" in paths
      after
        File.rm_rf!(sandbox)
        File.rm_rf!(outside)
      end
    end

    test "SAFETY: enforces maximum depth limit to prevent stack overflow" do
      # TreeWalker has a hard-coded max depth of 100 to prevent stack overflow
      # on maliciously deep directory structures
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-depth-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a directory structure deeper than the limit (105 levels)
        # This would cause stack overflow without protection
        deep_path =
          Enum.reduce(1..105, tmp_dir, fn i, acc ->
            path = Path.join(acc, "level#{i}")
            File.mkdir_p!(path)
            path
          end)

        # Add a file at the deepest level
        File.write!(Path.join(deep_path, "deep_file.txt"), "content")

        # Walk without explicit maxdepth - should hit internal limit
        entries = TreeWalker.walk(tmp_dir)
        basenames = Enum.map(entries, fn {path, _} -> Path.basename(path) end)

        # Should NOT find the file at depth 105 (beyond limit of 100)
        refute "deep_file.txt" in basenames

        # Should find directories up to the limit
        assert "level1" in basenames
        assert "level50" in basenames
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
