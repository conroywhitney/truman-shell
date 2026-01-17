defmodule TrumanShell.Stages.PipelineTest do
  @moduledoc """
  Integration tests for the full pipeline flow:
  Tokenizer → Parser → Expander → Executor → Redirector
  """
  use ExUnit.Case, async: true

  # These tests verify end-to-end behavior through TrumanShell.execute/1

  describe "full pipeline: simple commands" do
    test "pwd returns current directory" do
      {:ok, output} = TrumanShell.execute("pwd")
      assert String.trim(output) == File.cwd!()
    end

    test "echo returns arguments" do
      {:ok, output} = TrumanShell.execute("echo hello world")
      assert String.trim(output) == "hello world"
    end

    test "empty command returns error" do
      assert {:error, "Empty command"} = TrumanShell.execute("")
    end
  end

  describe "full pipeline: tilde expansion" do
    test "cd ~ expands to sandbox root" do
      {:ok, _} = TrumanShell.execute("cd ~")
      {:ok, pwd} = TrumanShell.execute("pwd")
      # After cd ~, pwd should be sandbox root (cwd)
      assert String.trim(pwd) == File.cwd!()
    end

    test "echo ~ expands tilde (shell behavior)" do
      {:ok, output} = TrumanShell.execute("echo ~")
      # Expander expands tilde in ALL args (correct shell behavior)
      assert String.trim(output) == File.cwd!()
    end

    test "echo ~/lib expands to path under sandbox" do
      {:ok, output} = TrumanShell.execute("echo ~/lib")
      expected = Path.join(File.cwd!(), "lib")
      assert String.trim(output) == expected
    end
  end

  describe "full pipeline: pipes" do
    test "echo piped to grep filters output" do
      {:ok, output} = TrumanShell.execute("echo hello | grep hello")
      assert String.trim(output) == "hello"
    end

    test "echo piped to grep with no match returns empty" do
      {:ok, output} = TrumanShell.execute("echo hello | grep world")
      assert output == ""
    end

    test "multi-stage pipe works" do
      {:ok, output} = TrumanShell.execute("echo line1 line2 line3 | head -1")
      assert String.trim(output) == "line1 line2 line3"
    end
  end

  describe "full pipeline: redirects" do
    setup do
      # Create a temp directory INSIDE sandbox using relative path
      rel_dir = ".test_tmp_#{:rand.uniform(100_000)}"
      tmp_dir = Path.join(File.cwd!(), rel_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir, rel_dir: rel_dir}
    end

    test "write redirect creates file", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      # Use RELATIVE path for redirect (like shell would parse)
      rel_file = "#{rel_dir}/output.txt"
      {:ok, _} = TrumanShell.execute("echo hello > #{rel_file}")

      full_path = Path.join(tmp_dir, "output.txt")
      assert File.exists?(full_path)
      assert File.read!(full_path) == "hello\n"
    end

    test "append redirect appends to file", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      # Pre-create file
      full_path = Path.join(tmp_dir, "append.txt")
      File.write!(full_path, "first\n")

      # Use relative path for redirect
      rel_file = "#{rel_dir}/append.txt"
      {:ok, _} = TrumanShell.execute("echo second >> #{rel_file}")

      assert File.read!(full_path) == "first\nsecond\n"
    end

    test "redirect outside sandbox fails with 404 error" do
      # Trying to write outside sandbox should fail
      {:error, msg} = TrumanShell.execute("echo hello > /tmp/outside_sandbox.txt")
      assert msg =~ "No such file or directory"
    end
  end

  describe "full pipeline: combined features" do
    setup do
      rel_dir = ".test_combined_#{:rand.uniform(100_000)}"
      tmp_dir = Path.join(File.cwd!(), rel_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir, rel_dir: rel_dir}
    end

    test "pipe and redirect work together", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      rel_file = "#{rel_dir}/filtered.txt"
      {:ok, _} = TrumanShell.execute("echo hello world | grep hello > #{rel_file}")

      full_path = Path.join(tmp_dir, "filtered.txt")
      assert File.exists?(full_path)
      assert File.read!(full_path) == "hello world\n"
    end

    test "tilde expansion with redirect", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      rel_file = "#{rel_dir}/tilde_test.txt"
      {:ok, _} = TrumanShell.execute("echo ~/lib > #{rel_file}")

      full_path = Path.join(tmp_dir, "tilde_test.txt")
      assert File.exists?(full_path)
      expected_content = Path.join(File.cwd!(), "lib") <> "\n"
      assert File.read!(full_path) == expected_content
    end
  end

  describe "full pipeline: tilde expansion in redirect targets" do
    setup do
      # Create a temp directory at sandbox root for tilde-relative paths
      rel_dir = ".test_tilde_redirect_#{:rand.uniform(100_000)}"
      tmp_dir = Path.join(File.cwd!(), rel_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir, rel_dir: rel_dir}
    end

    test "echo hi > ~/out.txt expands tilde in redirect target", %{rel_dir: rel_dir} do
      # ~/rel_dir/out.txt should expand to sandbox_root/rel_dir/out.txt
      {:ok, _} = TrumanShell.execute("echo hi > ~/#{rel_dir}/out.txt")

      full_path = Path.join([File.cwd!(), rel_dir, "out.txt"])
      assert File.exists?(full_path)
      assert File.read!(full_path) == "hi\n"
    end

    test "tilde redirect with pipe: cmd1 | cmd2 > ~/out.txt", %{rel_dir: rel_dir} do
      {:ok, _} = TrumanShell.execute("echo hello world | grep hello > ~/#{rel_dir}/piped.txt")

      full_path = Path.join([File.cwd!(), rel_dir, "piped.txt"])
      assert File.exists?(full_path)
      assert File.read!(full_path) == "hello world\n"
    end

    test "append redirect with tilde: echo more >> ~/log.txt", %{rel_dir: rel_dir} do
      # Create initial file
      full_path = Path.join([File.cwd!(), rel_dir, "log.txt"])
      File.write!(full_path, "first\n")

      {:ok, _} = TrumanShell.execute("echo second >> ~/#{rel_dir}/log.txt")

      assert File.read!(full_path) == "first\nsecond\n"
    end
  end

  describe "full pipeline: redirect edge cases" do
    setup do
      rel_dir = ".test_redirect_edge_#{:rand.uniform(100_000)}"
      tmp_dir = Path.join(File.cwd!(), rel_dir)
      # Create nested structure for relative path tests
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir, rel_dir: rel_dir}
    end

    test "redirect with ../: echo h > subdir/../out.txt stays in sandbox", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      # subdir/../out.txt resolves to out.txt in rel_dir (stays in sandbox)
      {:ok, _} = TrumanShell.execute("echo h > #{rel_dir}/subdir/../out.txt")

      full_path = Path.join(tmp_dir, "out.txt")
      assert File.exists?(full_path)
      assert File.read!(full_path) == "h\n"
    end

    test "redirect escaping sandbox with ../ fails", %{rel_dir: _rel_dir} do
      # Trying to escape sandbox should fail
      {:error, msg} = TrumanShell.execute("echo escape > ../../outside.txt")
      assert msg =~ "No such file or directory"
    end

    test "intermediate redirect: cmd1 > file.txt | cmd2 - first cmd redirect ignored", %{
      tmp_dir: tmp_dir,
      rel_dir: rel_dir
    } do
      # Current behavior: only last command's redirect applies
      # So cmd1's redirect to first.txt is ignored, output goes to stdout
      {:ok, output} = TrumanShell.execute("echo hello > #{rel_dir}/first.txt | grep hello")

      # The redirect on echo is ignored (only last cmd redirects apply)
      # So grep receives "hello" and outputs it
      assert String.trim(output) == "hello"

      # first.txt should NOT be created (redirect was ignored)
      first_path = Path.join(tmp_dir, "first.txt")
      refute File.exists?(first_path)
    end

    test "last command redirect: cmd1 | cmd2 > file.txt works", %{tmp_dir: tmp_dir, rel_dir: rel_dir} do
      {:ok, _} = TrumanShell.execute("echo hello world | grep hello > #{rel_dir}/last.txt")

      full_path = Path.join(tmp_dir, "last.txt")
      assert File.exists?(full_path)
      assert File.read!(full_path) == "hello world\n"
    end
  end
end
