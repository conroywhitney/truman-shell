defmodule TrumanShell.Commands.CatTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Cat
  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    test "returns file contents" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "hello.txt"), "Hello, World!\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Cat.handle(["hello.txt"], ctx)

        assert output == "Hello, World!\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "concatenates multiple files in order" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "a.txt"), "AAA\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "BBB\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Cat.handle(["a.txt", "b.txt"], ctx)

        assert output == "AAA\nBBB\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "stops on first missing file" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-stop-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "exists.txt"), "EXISTS\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        # Second file doesn't exist - should fail
        result = Cat.handle(["exists.txt", "missing.txt"], ctx)

        assert {:error, msg} = result
        assert msg =~ "missing.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        result = Cat.handle(["missing.txt"], ctx)

        assert {:error, msg} = result
        assert msg == "cat: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for directory" do
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config}

      result = Cat.handle(["lib"], ctx)

      assert {:error, msg} = result
      assert msg =~ "Is a directory"
    end

    test "returns error for file exceeding size limit (10MB)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-size-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file larger than 10MB limit (10.1MB = 10,100,000 bytes)
        # This prevents OOM attacks while allowing large source files
        large_content = String.duplicate("x", 10_100_000)
        File.write!(Path.join(tmp_dir, "huge.txt"), large_content)
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        result = Cat.handle(["huge.txt"], ctx)

        assert {:error, msg} = result
        assert msg =~ "File too large"
        assert msg =~ "10MB"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "reads from stdin when no file arguments provided" do
      # Unix behavior: `echo hello | cat` outputs "hello"
      config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      ctx = %Context{current_path: File.cwd!(), sandbox_config: config, stdin: "hello from stdin\n"}

      {:ok, output} = Cat.handle([], ctx)

      assert output == "hello from stdin\n"
    end

    test "explicit file argument takes precedence over stdin" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-cat-stdin-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "file.txt"), "from file\n")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config, stdin: "from stdin\n"}

        {:ok, output} = Cat.handle(["file.txt"], ctx)

        assert output == "from file\n"
        refute output =~ "stdin"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
