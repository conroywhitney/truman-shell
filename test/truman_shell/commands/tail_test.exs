defmodule TrumanShell.Commands.TailTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Tail
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  # Helper to create a temp file with numbered lines
  defp with_lines_file(n, fun) do
    tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-tail-#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    try do
      content = Enum.map_join(1..n, "\n", &"Line #{&1}")
      File.write!(Path.join(tmp_dir, "lines.txt"), content <> "\n")
      config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
      ctx = %Context{current_path: tmp_dir, sandbox_config: config}
      fun.(ctx)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  describe "handle/2" do
    test "returns last n lines with -n flag" do
      with_lines_file(10, fn context ->
        {:ok, output} = Tail.handle(["-n", "3", "lines.txt"], context)

        assert output == "Line 8\nLine 9\nLine 10\n"
      end)
    end

    test "returns last n lines with -NUM shorthand" do
      with_lines_file(10, fn context ->
        {:ok, output} = Tail.handle(["-5", "lines.txt"], context)

        assert output == "Line 6\nLine 7\nLine 8\nLine 9\nLine 10\n"
      end)
    end

    test "defaults to 10 lines when no -n specified" do
      with_lines_file(15, fn context ->
        {:ok, output} = Tail.handle(["lines.txt"], context)

        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 10
        assert List.first(lines) == "Line 6"
        assert List.last(lines) == "Line 15"
      end)
    end

    test "returns all lines if file has fewer than n" do
      with_lines_file(3, fn context ->
        {:ok, output} = Tail.handle(["-n", "10", "lines.txt"], context)

        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 3
      end)
    end

    test "returns error for missing file" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config}

      result = Tail.handle(["nonexistent.txt"], ctx)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "returns error for invalid -n value" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config}

      result = Tail.handle(["-n", "foobar", "mix.exs"], ctx)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end

    test "returns error for negative -n value" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config}

      result = Tail.handle(["-n", "-5", "mix.exs"], ctx)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end

    test "explicit file argument takes precedence over stdin" do
      # Unix behavior: `echo "stdin" | tail -n 1 file.txt` reads file.txt, ignores stdin
      with_lines_file(5, fn ctx ->
        ctx_with_stdin = %{ctx | stdin: "stdin line 1\nstdin line 2\n"}
        {:ok, output} = Tail.handle(["-n", "1", "lines.txt"], ctx_with_stdin)

        # Should read from file, not stdin
        assert output == "Line 5\n"
        refute output =~ "stdin"
      end)
    end

    test "uses stdin when no file argument provided" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config, stdin: "stdin line 1\nstdin line 2\n"}
      {:ok, output} = Tail.handle(["-n", "1"], ctx)

      assert output == "stdin line 2\n"
    end
  end
end
