defmodule TrumanShell.Commands.LsTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Ls

  @moduletag :commands

  describe "handle/2" do
    test "lists files in current directory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      {:ok, output} = Ls.handle([], context)

      assert output =~ "mix.exs"
    end

    test "lists files in specified directory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      {:ok, output} = Ls.handle(["lib"], context)

      assert output =~ "truman_shell.ex"
    end

    test "appends / to directory names" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      {:ok, output} = Ls.handle([], context)

      assert output =~ "lib/"
      assert output =~ "test/"
    end

    test "returns error for non-existent directory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Ls.handle(["nonexistent_dir"], context)

      assert {:error, message} = result
      assert message == "ls: nonexistent_dir: No such file or directory\n"
    end

    test "rejects unsupported flags" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Ls.handle(["-la"], context)

      assert {:error, message} = result
      assert message =~ "invalid option"
    end

    test "rejects multiple path arguments" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Ls.handle(["lib", "test"], context)

      assert {:error, message} = result
      assert message =~ "too many arguments"
    end

    test "rejects access to paths outside sandbox (404 principle)" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Ls.handle(["/etc"], context)

      assert {:error, message} = result
      assert message =~ "No such file or directory"
      # Must NOT reveal that the path exists
      refute message =~ "permission"
    end

    test "truncates output for large directories" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "truman-test-ls-truncation-#{:rand.uniform(100_000)}")

      File.mkdir_p!(tmp_dir)

      # Create 250 files (exceeds 200 line limit)
      for i <- 1..250 do
        File.write!(Path.join(tmp_dir, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}
        {:ok, output} = Ls.handle(["."], context)

        assert output =~ "... (50 more entries, 250 total)"

        lines = String.split(output, "\n", trim: true)
        # 200 files + 1 truncation message
        assert length(lines) == 201
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
