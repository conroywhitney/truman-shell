defmodule TrumanShell.Stages.RedirectorTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Stages.Redirector

  @moduletag :stages

  describe "apply/3" do
    @tag :tmp_dir
    test "write redirect creates file with output", %{tmp_dir: sandbox} do
      output = "hello world\n"
      redirects = [{:stdout, "test.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:ok, ""} = result
      assert File.read!(Path.join(sandbox, "test.txt")) == "hello world\n"
    end

    @tag :tmp_dir
    test "append redirect appends to existing file", %{tmp_dir: sandbox} do
      # Create existing file
      target = Path.join(sandbox, "existing.txt")
      File.write!(target, "line 1\n")

      output = "line 2\n"
      redirects = [{:stdout_append, "existing.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:ok, ""} = result
      assert File.read!(target) == "line 1\nline 2\n"
    end

    @tag :tmp_dir
    test "no redirects passes output through unchanged", %{tmp_dir: sandbox} do
      output = "hello world\n"
      redirects = []
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:ok, "hello world\n"} = result
    end

    @tag :tmp_dir
    test "redirect outside sandbox returns error (404 principle)", %{tmp_dir: sandbox} do
      output = "should not write\n"
      redirects = [{:stdout, "/etc/passwd"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:error, error_msg} = result
      assert error_msg =~ "No such file or directory"
      refute error_msg =~ "permission" or error_msg =~ "denied"
    end

    @tag :tmp_dir
    test "redirect with path traversal returns error", %{tmp_dir: sandbox} do
      output = "should not write\n"
      redirects = [{:stdout, "../../escape.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:error, error_msg} = result
      assert error_msg =~ "No such file or directory"
    end

    @tag :tmp_dir
    test "multiple redirects: last file gets output, earlier truncated", %{tmp_dir: sandbox} do
      # Bash behavior: echo hello > a.txt > b.txt creates empty a.txt, "hello\n" in b.txt
      output = "hello\n"
      redirects = [{:stdout, "first.txt"}, {:stdout, "second.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:ok, ""} = result
      assert File.read!(Path.join(sandbox, "first.txt")) == ""
      assert File.read!(Path.join(sandbox, "second.txt")) == "hello\n"
    end

    @tag :tmp_dir
    test "redirect to subdirectory works", %{tmp_dir: sandbox} do
      # Create subdirectory
      subdir = Path.join(sandbox, "subdir")
      File.mkdir_p!(subdir)

      output = "in subdir\n"
      redirects = [{:stdout, "subdir/file.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:ok, ""} = result
      assert File.read!(Path.join(subdir, "file.txt")) == "in subdir\n"
    end

    @tag :tmp_dir
    test "redirect to nonexistent parent directory returns error", %{tmp_dir: sandbox} do
      output = "should not write\n"
      redirects = [{:stdout, "nonexistent/file.txt"}]
      context = %{sandbox_root: sandbox, current_dir: sandbox}

      result = Redirector.apply(output, redirects, context)

      assert {:error, error_msg} = result
      assert error_msg =~ "No such file or directory"
    end
  end
end
