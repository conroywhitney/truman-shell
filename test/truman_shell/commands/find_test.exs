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
  end
end
