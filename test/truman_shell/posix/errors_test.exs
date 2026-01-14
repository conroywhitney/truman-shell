defmodule TrumanShell.Posix.ErrorsTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Posix.Errors

  describe "to_message/1" do
    test "converts :enoent to 'No such file or directory'" do
      assert Errors.to_message(:enoent) == "No such file or directory"
    end

    test "converts :eisdir to 'Is a directory'" do
      assert Errors.to_message(:eisdir) == "Is a directory"
    end

    test "converts :enotdir to 'Not a directory'" do
      assert Errors.to_message(:enotdir) == "Not a directory"
    end

    test "converts :eacces to 'Permission denied'" do
      assert Errors.to_message(:eacces) == "Permission denied"
    end

    test "converts :enospc to 'No space left on device'" do
      assert Errors.to_message(:enospc) == "No space left on device"
    end

    test "converts :erofs to 'Read-only file system'" do
      assert Errors.to_message(:erofs) == "Read-only file system"
    end

    test "converts :eexist to 'File exists'" do
      assert Errors.to_message(:eexist) == "File exists"
    end

    test "converts :exdev to 'Invalid cross-device link'" do
      assert Errors.to_message(:exdev) == "Invalid cross-device link"
    end

    test "converts unknown errors to generic message (prevents info leakage)" do
      # Unknown errors should NOT stringify the atom - could leak implementation details
      assert Errors.to_message(:unknown_error) == "Operation not permitted"
      assert Errors.to_message(:eloop) == "Operation not permitted"
      assert Errors.to_message(:some_internal_error) == "Operation not permitted"
    end
  end
end
