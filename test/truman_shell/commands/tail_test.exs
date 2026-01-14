defmodule TrumanShell.Commands.TailTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Tail

  @moduletag :commands

  # Helper to create a temp file with numbered lines
  defp with_lines_file(n, fun) do
    tmp_dir = Path.join(System.tmp_dir!(), "truman-test-tail-#{:rand.uniform(100_000)}")
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
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Tail.handle(["nonexistent.txt"], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "returns error for invalid -n value" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Tail.handle(["-n", "foobar", "mix.exs"], context)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end

    test "returns error for negative -n value" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Tail.handle(["-n", "-5", "mix.exs"], context)

      assert {:error, msg} = result
      assert msg =~ "invalid number of lines"
    end
  end
end
