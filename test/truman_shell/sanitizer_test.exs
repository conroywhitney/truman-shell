defmodule TrumanShell.SanitizerTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Sanitizer

  describe "validate_path/2" do
    @tag :tmp_dir
    test "rejects symlink that escapes sandbox", %{tmp_dir: sandbox} do
      # Create a symlink inside sandbox that points to /tmp (outside sandbox)
      symlink_path = Path.join(sandbox, "escape_link")
      File.ln_s("/tmp", symlink_path)

      # The symlink exists inside sandbox, but points outside
      result = Sanitizer.validate_path("escape_link", sandbox)

      # Should be rejected because following it escapes the sandbox
      assert {:error, :outside_sandbox} = result
    end

    test "allows path within sandbox" do
      sandbox = "/tmp/truman-test"
      path = "subdir/file.txt"

      result = Sanitizer.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test/subdir/file.txt"} = result
    end

    test "rejects path traversal attack" do
      sandbox = "/tmp/truman-test"
      path = "../../../etc/passwd"

      result = Sanitizer.validate_path(path, sandbox)

      assert {:error, :outside_sandbox} = result
    end

    test "rejects absolute path outside sandbox" do
      # Absolute paths outside sandbox are rejected (AIITL transparency)
      # This is more honest than silently confining /etc -> sandbox/etc
      sandbox = "/tmp/truman-test"
      path = "/etc/passwd"

      result = Sanitizer.validate_path(path, sandbox)

      # Path is rejected, not confined
      assert {:error, :outside_sandbox} = result
    end

    test "allows absolute path within sandbox" do
      # Absolute paths that are already within sandbox should work
      sandbox = "/tmp/truman-test"
      path = "/tmp/truman-test/subdir/file.txt"

      result = Sanitizer.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test/subdir/file.txt"} = result
    end

    test "allows current directory (.)" do
      sandbox = "/tmp/truman-test"
      path = "."

      result = Sanitizer.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test"} = result
    end
  end
end
