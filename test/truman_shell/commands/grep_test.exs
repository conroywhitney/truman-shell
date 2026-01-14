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

    test "grep -n shows line numbers" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-n-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "foo\nbar\nfoo again\nbaz\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-n", "foo", "test.txt"], context)

        assert output == "1:foo\n3:foo again\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -i matches case insensitively" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-i-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "Hello\nhello\nHELLO\nworld\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-i", "hello", "test.txt"], context)

        assert output == "Hello\nhello\nHELLO\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -v inverts match" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-v-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "keep\nremove\nkeep too\nremove also\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-v", "remove", "test.txt"], context)

        assert output == "keep\nkeep too\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -A shows lines after match" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-A-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "before\nmatch\nafter1\nafter2\nafter3\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-A", "2", "match", "test.txt"], context)

        assert output == "match\nafter1\nafter2\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -B shows lines before match" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-B-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "before2\nbefore1\nmatch\nafter\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-B", "2", "match", "test.txt"], context)

        assert output == "before2\nbefore1\nmatch\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -C shows context both sides" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-C-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "line1\nbefore\nmatch\nafter\nline5\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Grep.handle(["-C", "1", "match", "test.txt"], context)

        assert output == "before\nmatch\nafter\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -A rejects negative context values" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-neg-A-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "content\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["-A", "-5", "pattern", "test.txt"], context)

        assert msg == "grep: invalid context length argument\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -B rejects negative context values" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-neg-B-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "content\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["-B", "-3", "pattern", "test.txt"], context)

        assert msg == "grep: invalid context length argument\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grep -C rejects negative context values" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-grep-neg-C-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "content\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Grep.handle(["-C", "-2", "pattern", "test.txt"], context)

        assert msg == "grep: invalid context length argument\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
