defmodule TrumanShell.Commands.FindTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Find
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    test "find . -name pattern finds matching files" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create directory structure
        File.mkdir_p!(Path.join(tmp_dir, "src"))
        File.write!(Path.join(tmp_dir, "mix.exs"), "")
        File.write!(Path.join(tmp_dir, "README.md"), "")
        File.write!(Path.join([tmp_dir, "src", "app.ex"]), "")
        File.write!(Path.join([tmp_dir, "src", "helper.ex"]), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-name", "*.ex"], ctx)

        # Should find .ex files (not .exs - glob is exact)
        assert output =~ "src/app.ex"
        assert output =~ "src/helper.ex"
        # Should not find .md or .exs files
        refute output =~ "README.md"
        refute output =~ "mix.exs"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find returns error for path outside sandbox (404 principle)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:error, msg} = Find.handle(["/etc", "-name", "*.conf"], ctx)

        assert msg == "find: /etc: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find with missing -name returns error" do
      sandbox = Path.join(File.cwd!(), "tmp")
      File.mkdir_p!(sandbox)
      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      ctx = %Context{current_path: sandbox, sandbox_config: config}

      {:error, msg} = Find.handle([".", "-name"], ctx)

      assert msg =~ "missing argument"
    end

    test "find -type f finds only files" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-type-f-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.write!(Path.join(tmp_dir, "file.txt"), "")
        File.write!(Path.join([tmp_dir, "subdir", "nested.txt"]), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-type", "f"], ctx)

        assert output =~ "file.txt"
        assert output =~ "nested.txt"
        refute output =~ "subdir\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find -type d finds only directories" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-type-d-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.mkdir_p!(Path.join([tmp_dir, "subdir", "nested"]))
        File.write!(Path.join(tmp_dir, "file.txt"), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-type", "d"], ctx)

        assert output =~ "subdir"
        assert output =~ "nested"
        refute output =~ "file.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find -maxdepth limits search depth" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-maxdepth-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join([tmp_dir, "a", "b", "c"]))
        File.write!(Path.join(tmp_dir, "root.txt"), "")
        File.write!(Path.join([tmp_dir, "a", "level1.txt"]), "")
        File.write!(Path.join([tmp_dir, "a", "b", "level2.txt"]), "")
        File.write!(Path.join([tmp_dir, "a", "b", "c", "level3.txt"]), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-maxdepth", "2", "-name", "*.txt"], ctx)

        assert output =~ "root.txt"
        assert output =~ "level1.txt"
        refute output =~ "level2.txt"
        refute output =~ "level3.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find -maxdepth 0 returns only the starting directory" do
      # GNU find with -maxdepth 0 only examines the start point itself
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-maxdepth0-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.write!(Path.join(tmp_dir, "file.txt"), "")
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: tmp_dir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-maxdepth", "0"], ctx)

        # With maxdepth 0, should only return "." (the start point)
        # Should NOT descend into any children
        assert output == ".\n"
        refute output =~ "subdir"
        refute output =~ "file.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find . uses current_path, not home_path (P1 fix)" do
      # When current_path != home_path (after cd), find . should search current_path
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-find-cwd-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create structure: sandbox/subdir/found.txt and sandbox/root.txt
        subdir = Path.join(tmp_dir, "subdir")
        File.mkdir_p!(subdir)
        File.write!(Path.join(subdir, "found.txt"), "in subdir")
        File.write!(Path.join(tmp_dir, "root.txt"), "at root")

        # Simulate: cd subdir (current_path = subdir, home_path = sandbox root)
        config = %SandboxConfig{allowed_paths: [tmp_dir], home_path: tmp_dir}
        ctx = %Context{current_path: subdir, sandbox_config: config}

        {:ok, output} = Find.handle([".", "-name", "*.txt"], ctx)

        # Should find subdir/found.txt, NOT sandbox/root.txt
        assert output =~ "found.txt"
        refute output =~ "root.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
