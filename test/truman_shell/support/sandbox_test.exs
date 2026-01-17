defmodule TrumanShell.Support.SandboxTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Support.Sandbox

  describe "validate_path/2" do
    @tag :tmp_dir
    test "rejects symlink with absolute target outside sandbox", %{tmp_dir: sandbox} do
      # Create a symlink inside sandbox that points to /tmp (outside sandbox)
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("/tmp", symlink_path)

      # The symlink exists inside sandbox, but points outside
      result = Sandbox.validate_path("escape_link", sandbox)

      # Should be rejected because absolute target escapes sandbox
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "rejects symlink with absolute target even inside sandbox", %{tmp_dir: sandbox} do
      # Even if absolute path points inside sandbox, it's rejected
      # because Path.safe_relative can't verify absolute targets safely
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "abs_link")
      File.ln_s(inside_dir, symlink_path)

      result = Sandbox.validate_path("abs_link", sandbox)

      # Rejected: absolute symlink targets are unverifiable
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "rejects symlink with relative escaping target", %{tmp_dir: sandbox} do
      # Symlink with relative path that escapes via ..
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("../../etc/passwd", symlink_path)

      result = Sandbox.validate_path("escape_link", sandbox)

      # Rejected: relative target escapes via ..
      assert {:error, :outside_sandbox} = result
    end

    @tag :tmp_dir
    test "allows symlink with safe relative target", %{tmp_dir: sandbox} do
      # Create target directory and symlink with relative path
      inside_dir = Path.join(sandbox, "inside")
      File.mkdir_p!(inside_dir)

      symlink_path = Path.join(sandbox, "safe_link")
      File.ln_s("inside", symlink_path)

      result = Sandbox.validate_path("safe_link", sandbox)

      # Allowed: relative target stays within sandbox
      assert {:ok, _} = result
    end

    test "allows path within sandbox" do
      sandbox = "/tmp/truman-test"
      path = "subdir/file.txt"

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test/subdir/file.txt"} = result
    end

    test "rejects path traversal attack" do
      sandbox = "/tmp/truman-test"
      path = "../../../etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects absolute path outside sandbox" do
      # Absolute paths outside sandbox are rejected (AIITL transparency)
      # This is more honest than silently confining /etc -> sandbox/etc
      sandbox = "/tmp/truman-test"
      path = "/etc/passwd"

      result = Sandbox.validate_path(path, sandbox)

      # Path is rejected, not confined
      assert {:error, :outside_sandbox} = result
    end

    test "allows absolute path within sandbox" do
      # Absolute paths that are already within sandbox should work
      sandbox = "/tmp/truman-test"
      path = "/tmp/truman-test/subdir/file.txt"

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test/subdir/file.txt"} = result
    end

    test "rejects path with sandbox prefix but different directory" do
      # Security: /tmp/truman-test2 should NOT pass for sandbox /tmp/truman-test
      # This catches the string prefix bug where "truman-test2" starts with "truman-test"
      sandbox = "/tmp/truman-test"
      path = "/tmp/truman-test2/secret"

      result = Sandbox.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "allows current directory (.)" do
      sandbox = "/tmp/truman-test"
      path = "."

      result = Sandbox.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test"} = result
    end
  end
end
