defmodule TrumanShell.Commands.CatTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Cat

  @moduletag :commands

  describe "handle/2" do
    test "returns file contents" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "hello.txt"), "Hello, World!\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Cat.handle(["hello.txt"], context)

        assert output == "Hello, World!\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "concatenates multiple files in order" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "a.txt"), "AAA\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "BBB\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Cat.handle(["a.txt", "b.txt"], context)

        assert output == "AAA\nBBB\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "stops on first missing file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-stop-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "exists.txt"), "EXISTS\n")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        # Second file doesn't exist - should fail
        result = Cat.handle(["exists.txt", "missing.txt"], context)

        assert {:error, msg} = result
        assert msg =~ "missing.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        result = Cat.handle(["missing.txt"], context)

        assert {:error, msg} = result
        assert msg == "cat: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for directory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Cat.handle(["lib"], context)

      assert {:error, msg} = result
      assert msg =~ "Is a directory"
    end

    test "returns error for file exceeding size limit (10MB)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-size-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file larger than 10MB limit (10.1MB = 10,100,000 bytes)
        # This prevents OOM attacks while allowing large source files
        large_content = String.duplicate("x", 10_100_000)
        File.write!(Path.join(tmp_dir, "huge.txt"), large_content)
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        result = Cat.handle(["huge.txt"], context)

        assert {:error, msg} = result
        assert msg =~ "File too large"
        assert msg =~ "10MB"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
