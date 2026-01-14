defmodule TrumanShell.Commands.GrepTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Grep

  @moduletag :commands

  describe "handle/2" do
    test "finds lines matching pattern in file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = """
        apple pie
        banana bread
        apple crisp
        cherry tart
        """

        File.write!(Path.join(tmp_dir, "recipes.txt"), content)
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["apple", "recipes.txt"], context)

        assert output == "apple pie\napple crisp\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns empty string when no matches" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-nomatch-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["banana", "hello.txt"], context)

        assert output == ""
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["pattern", "missing.txt"], context)

        assert msg == "grep: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "searches multiple files in order with filename prefix" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "a.txt"), "foo one\nbar\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "baz\nfoo two\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["foo", "a.txt", "b.txt"], context)

        # With multiple files, grep prefixes each match with filename
        assert output == "a.txt:foo one\nb.txt:foo two\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error when missing pattern or file" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      {:error, msg} = Grep.handle([], context)

      assert msg == "grep: missing pattern or file operand\n"
    end

    test "returns error for path outside sandbox (404 principle)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["pattern", "/etc/passwd"], context)

        assert msg == "grep: /etc/passwd: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -r searches directory recursively" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-recursive-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create directory structure
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.write!(Path.join(tmp_dir, "root.txt"), "TODO: fix this\n")
        File.write!(Path.join([tmp_dir, "subdir", "nested.txt"]), "TODO: add tests\nDONE: complete\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-r", "TODO", "."], context)

        # Should find matches in both files with file:line format
        assert output =~ "root.txt:TODO: fix this"
        assert output =~ "subdir/nested.txt:TODO: add tests"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -r respects sandbox boundary" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-r-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["-r", "pattern", "/etc"], context)

        assert msg == "grep: /etc: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
