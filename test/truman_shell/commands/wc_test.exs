defmodule TrumanShell.Commands.WcTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Wc

  @moduletag :commands

  describe "handle/2" do
    test "returns line, word, and character counts" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = "hello world\nfoo bar baz\n"
        File.write!(Path.join(tmp_dir, "test.txt"), content)
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Wc.handle(["test.txt"], context)

        # Format: lines words chars filename
        assert output =~ "2"
        assert output =~ "5"
        assert output =~ "24"
        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "counts multiple files with total" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "a.txt"), "one two\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "three\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Wc.handle(["a.txt", "b.txt"], context)

        # Should show totals for multiple files
        assert output =~ "a.txt"
        assert output =~ "b.txt"
        assert output =~ "total"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Wc.handle(["missing.txt"], context)

        assert msg == "wc: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for path outside sandbox (404 principle)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Wc.handle(["/etc/passwd"], context)

        assert msg == "wc: /etc/passwd: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -l shows only line count" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-l-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "line1\nline2\nline3\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Wc.handle(["-l", "test.txt"], context)

        # Should show only line count and filename
        assert output =~ "3"
        assert output =~ "test.txt"
        # Should not show word or char counts
        refute output =~ ~r/\s+\d+\s+\d+\s+\d+\s/
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -w shows only word count" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-w-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "one two three four five\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Wc.handle(["-w", "test.txt"], context)

        assert output =~ "5"
        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -c shows only byte count" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-wc-c-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = "hello\n"
        File.write!(Path.join(tmp_dir, "test.txt"), content)
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Wc.handle(["-c", "test.txt"], context)

        assert output =~ "6"
        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
