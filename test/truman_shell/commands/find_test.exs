defmodule TrumanShell.Commands.FindTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Find

  @moduletag :commands

  describe "handle/2" do
    test "find . -name pattern finds matching files" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-find-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create directory structure
        File.mkdir_p!(Path.join(tmp_dir, "src"))
        File.write!(Path.join(tmp_dir, "mix.exs"), "")
        File.write!(Path.join(tmp_dir, "README.md"), "")
        File.write!(Path.join([tmp_dir, "src", "app.ex"]), "")
        File.write!(Path.join([tmp_dir, "src", "helper.ex"]), "")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Find.handle([".", "-name", "*.ex"], context)

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
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-find-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:error, msg} = Find.handle(["/etc", "-name", "*.conf"], context)

        assert msg == "find: /etc: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find with missing -name returns error" do
      context = %{sandbox_root: "/tmp", current_dir: "/tmp"}

      {:error, msg} = Find.handle([".", "-name"], context)

      assert msg =~ "missing argument"
    end

    test "find -type f finds only files" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-find-type-f-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.write!(Path.join(tmp_dir, "file.txt"), "")
        File.write!(Path.join([tmp_dir, "subdir", "nested.txt"]), "")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Find.handle([".", "-type", "f"], context)

        assert output =~ "file.txt"
        assert output =~ "nested.txt"
        refute output =~ "subdir\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find -type d finds only directories" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-find-type-d-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join(tmp_dir, "subdir"))
        File.mkdir_p!(Path.join([tmp_dir, "subdir", "nested"]))
        File.write!(Path.join(tmp_dir, "file.txt"), "")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Find.handle([".", "-type", "d"], context)

        assert output =~ "subdir"
        assert output =~ "nested"
        refute output =~ "file.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "find -maxdepth limits search depth" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-find-maxdepth-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.mkdir_p!(Path.join([tmp_dir, "a", "b", "c"]))
        File.write!(Path.join(tmp_dir, "root.txt"), "")
        File.write!(Path.join([tmp_dir, "a", "level1.txt"]), "")
        File.write!(Path.join([tmp_dir, "a", "b", "level2.txt"]), "")
        File.write!(Path.join([tmp_dir, "a", "b", "c", "level3.txt"]), "")
        context = %{sandbox_root: tmp_dir, current_dir: tmp_dir}

        {:ok, output} = Find.handle([".", "-maxdepth", "2", "-name", "*.txt"], context)

        assert output =~ "root.txt"
        assert output =~ "level1.txt"
        refute output =~ "level2.txt"
        refute output =~ "level3.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
