defmodule TrumanShell.SanitizerTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Sanitizer

  describe "validate_path/2" do
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

    test "confines absolute path within sandbox" do
      # Elixir's Path.join strips leading slashes, so /etc/passwd
      # becomes etc/passwd within the sandbox - this is secure behavior
      sandbox = "/tmp/truman-test"
      path = "/etc/passwd"

      result = Sanitizer.validate_path(path, sandbox)

      # Path is confined, not escaped
      assert {:ok, "/tmp/truman-test/etc/passwd"} = result
    end

    test "allows current directory (.)" do
      sandbox = "/tmp/truman-test"
      path = "."

      result = Sanitizer.validate_path(path, sandbox)

      assert {:ok, "/tmp/truman-test"} = result
    end
  end
end
