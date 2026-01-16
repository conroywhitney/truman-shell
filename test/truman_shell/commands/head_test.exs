defmodule TrumanShell.Commands.HeadTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Head

  @moduletag :commands

  # Helper to create a temp file with numbered lines
  defp with_lines_file(n, fun) do
    tmp_dir = Path.join(System.tmp_dir!(), "truman-test-head-#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    try do
      content = Enum.map_join(1..n, "\n", &"Line #{&1}")
      File.write!(Path.join(tmp_dir, "lines.txt"), content <> "\n")
      context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}
      fun.(context)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  describe "handle/2" do
    test "returns first n lines with -n flag" do
      with_lines_file(10, fn context ->
        {:ok, output} = Head.handle(["-n", "3", "lines.txt"], context)

        assert output == "Line 1\nLine 2\nLine 3\n"
      end)
    end

    test "returns first n lines with -NUM shorthand" do
      with_lines_file(10, fn context ->
        {:ok, output} = Head.handle(["-5", "lines.txt"], context)

        assert output == "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n"
      end)
    end

    test "returns exactly one line with -1" do
      with_lines_file(10, fn context ->
        {:ok, output} = Head.handle(["-1", "lines.txt"], context)

        assert output == "Line 1\n"
      end)
    end

    test "defaults to 10 lines when no -n specified" do
      with_lines_file(15, fn context ->
        {:ok, output} = Head.handle(["lines.txt"], context)

        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 10
        assert List.first(lines) == "Line 1"
        assert List.last(lines) == "Line 10"
      end)
    end

    test "returns all lines if file has fewer than n" do
      with_lines_file(3, fn context ->
        {:ok, output} = Head.handle(["-n", "10", "lines.txt"], context)

        # File only has 3 lines + trailing newline = 4 "lines" when split
        # But we trim, so we get 3 content lines
        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 3
      end)
    end

    test "returns error for missing file" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Head.handle(["nonexistent.txt"], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "returns error for invalid -n value" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Head.handle(["-n", "foobar", "mix.exs"], context)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end

    test "returns error for negative -n value" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Head.handle(["-n", "-5", "mix.exs"], context)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end

    test "explicit file argument takes precedence over stdin" do
      # Unix behavior: `echo "stdin" | head -n 1 file.txt` reads file.txt, ignores stdin
      with_lines_file(5, fn context ->
        context_with_stdin = Map.put(context, :stdin, "stdin line 1\nstdin line 2\n")
        {:ok, output} = Head.handle(["-n", "1", "lines.txt"], context_with_stdin)

        # Should read from file, not stdin
        assert output == "Line 1\n"
        refute output =~ "stdin"
      end)
    end

    test "uses stdin when no file argument provided" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!(), stdin: "stdin line 1\nstdin line 2\n"}
      {:ok, output} = Head.handle(["-n", "1"], context)

      assert output == "stdin line 1\n"
    end

    test "empty stdin is valid and returns empty output" do
      # Unix behavior: empty stdin is valid input, not an error
      # `printf "" | head -n 2` returns empty output, not "missing file operand"
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!(), stdin: ""}
      {:ok, output} = Head.handle(["-n", "2"], context)

      assert output == ""
    end
  end
end
