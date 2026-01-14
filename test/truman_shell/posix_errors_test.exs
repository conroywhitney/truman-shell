defmodule TrumanShell.PosixErrorsTest do
  use ExUnit.Case, async: true

  alias TrumanShell.PosixErrors

  describe "to_message/1" do
    test "converts :enoent to 'No such file or directory'" do
      assert PosixErrors.to_message(:enoent) == "No such file or directory"
    end

    test "converts :eisdir to 'Is a directory'" do
      assert PosixErrors.to_message(:eisdir) == "Is a directory"
    end

    test "converts :enotdir to 'Not a directory'" do
      assert PosixErrors.to_message(:enotdir) == "Not a directory"
    end

    test "converts :eacces to 'Permission denied'" do
      assert PosixErrors.to_message(:eacces) == "Permission denied"
    end

    test "converts :enospc to 'No space left on device'" do
      assert PosixErrors.to_message(:enospc) == "No space left on device"
    end

    test "converts :erofs to 'Read-only file system'" do
      assert PosixErrors.to_message(:erofs) == "Read-only file system"
    end

    test "converts :eexist to 'File exists'" do
      assert PosixErrors.to_message(:eexist) == "File exists"
    end

    test "converts :exdev to 'Invalid cross-device link'" do
      assert PosixErrors.to_message(:exdev) == "Invalid cross-device link"
    end

    test "converts unknown errors to string representation" do
      assert PosixErrors.to_message(:unknown_error) == "unknown_error"
      assert PosixErrors.to_message(:eloop) == "eloop"
    end
  end
end
