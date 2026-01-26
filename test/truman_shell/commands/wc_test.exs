defmodule TrumanShell.Commands.WcTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Wc
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    test "returns line, word, and character counts" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = "hello world\nfoo bar baz\n"
        File.write!(Path.join(tmp_dir, "test.txt"), content)
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["test.txt"], ctx)

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
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "a.txt"), "one two\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "three\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["a.txt", "b.txt"], ctx)

        # Should show totals for multiple files
        assert output =~ "a.txt"
        assert output =~ "b.txt"
        assert output =~ "total"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:error, msg} = Wc.handle(["missing.txt"], ctx)

        assert msg == "wc: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for path outside sandbox (404 principle)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:error, msg} = Wc.handle(["/etc/passwd"], ctx)

        assert msg == "wc: /etc/passwd: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -l shows only line count" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-l-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "line1\nline2\nline3\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["-l", "test.txt"], ctx)

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
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-w-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test.txt"), "one two three four five\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["-w", "test.txt"], ctx)

        assert output =~ "5"
        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -c shows only byte count" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-c-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = "hello\n"
        File.write!(Path.join(tmp_dir, "test.txt"), content)
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["-c", "test.txt"], ctx)

        assert output =~ "6"
        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc -c counts BYTES not graphemes (Unicode correctness)" do
      # 😄 is 4 UTF-8 bytes but 1 grapheme
      # GNU wc -c counts bytes, so "😄\n" should be 5 bytes (4 + newline)
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-unicode-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = "😄\n"
        File.write!(Path.join(tmp_dir, "emoji.txt"), content)
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["-c", "emoji.txt"], ctx)

        # Must be 5 bytes, NOT 2 graphemes
        assert output =~ ~r/^\s*5\s+emoji\.txt/
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "wc on zero-length file returns 0 0 0" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-empty-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "empty.txt"), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Wc.handle(["empty.txt"], ctx)

        # Should show 0 lines, 0 words, 0 chars
        assert output =~ ~r/^\s*0\s+0\s+0\s+empty\.txt/
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "explicit file argument takes precedence over stdin" do
      # Unix behavior: `echo "stdin" | wc -l file.txt` reads file.txt, ignores stdin
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-wc-prec-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "file.txt"), "one\ntwo\nthree\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config, stdin: "stdin has ten\nlines here\n"}

        {:ok, output} = Wc.handle(["-l", "file.txt"], ctx)

        # Should show 3 lines (from file), not 2 (from stdin)
        assert output =~ ~r/^\s*3\s+file\.txt/
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "uses stdin when no file argument provided" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config, stdin: "one\ntwo\nthree\n"}

      {:ok, output} = Wc.handle(["-l"], ctx)

      # Should count 3 lines from stdin
      assert output =~ "3"
    end
  end
end
