defmodule TrumanShell.Config.SandboxTest do
  @moduledoc """
  Tests for Config.Sandbox - pure struct validation.

  These tests use NO YAML files, NO file I/O.
  All validation is done on structs with test data.

  For file discovery and YAML parsing tests, see config_test.exs.
  """
  use ExUnit.Case, async: true

  alias TrumanShell.Config.Sandbox

  describe "new/2 - basic validation" do
    test "succeeds when home_path equals allowed_path" do
      assert {:ok, sandbox} = Sandbox.new(["/project"], "/project")
      assert sandbox.allowed_paths == ["/project"]
      assert sandbox.home_path == "/project"
    end

    test "succeeds when home_path is subdirectory of allowed_path" do
      assert {:ok, sandbox} = Sandbox.new(["/project"], "/project/src")
      assert sandbox.home_path == "/project/src"
    end

    test "fails when home_path is outside allowed_paths" do
      assert {:error, msg} = Sandbox.new(["/project"], "/elsewhere")
      assert msg =~ "home_path must be within one of the allowed_paths"
    end

    test "fails when allowed_paths list is empty" do
      assert {:error, msg} = Sandbox.new([], "/project")
      assert msg =~ "sandbox must have at least one allowed_path"
    end
  end

  describe "new/2 - multiple allowed_paths" do
    test "succeeds when home_path is in any allowed_path" do
      allowed = ["/project", "/libs"]
      assert {:ok, sandbox} = Sandbox.new(allowed, "/libs")
      assert sandbox.home_path == "/libs"
    end

    test "succeeds when home_path is subdirectory of second allowed_path" do
      allowed = ["/project", "/libs"]
      assert {:ok, sandbox} = Sandbox.new(allowed, "/libs/elixir")
      assert sandbox.home_path == "/libs/elixir"
    end

    test "fails when home_path is outside all allowed_paths" do
      allowed = ["/project", "/libs"]
      assert {:error, _} = Sandbox.new(allowed, "/tmp")
    end
  end

  describe "new/2 - path boundary edge cases" do
    test "rejects similar prefix that isn't actually within root" do
      # /project2 is NOT within /project
      assert {:error, _} = Sandbox.new(["/project"], "/project2")
    end

    test "handles trailing slashes correctly" do
      # Both with and without trailing slash should work
      assert {:ok, _} = Sandbox.new(["/project/"], "/project")
      assert {:ok, _} = Sandbox.new(["/project"], "/project/")
    end

    test "handles deeply nested paths" do
      assert {:ok, sandbox} = Sandbox.new(["/project"], "/project/a/b/c/d/e")
      assert sandbox.home_path == "/project/a/b/c/d/e"
    end
  end

  describe "path_allowed?/2 (delegates to DomePath.within?)" do
    setup do
      {:ok, sandbox} = Sandbox.new(["/project", "/libs"], "/project")
      %{sandbox: sandbox}
    end

    test "returns true for path in first root", %{sandbox: sandbox} do
      assert Sandbox.path_allowed?(sandbox, "/project/src/file.ex")
    end

    test "returns true for path in second root", %{sandbox: sandbox} do
      assert Sandbox.path_allowed?(sandbox, "/libs/dep/lib.ex")
    end

    test "returns false for path outside all allowed_paths", %{sandbox: sandbox} do
      refute Sandbox.path_allowed?(sandbox, "/etc/passwd")
    end

    test "returns false for similar prefix attack", %{sandbox: sandbox} do
      # /project2 is NOT within /project - DomePath.within? handles this
      refute Sandbox.path_allowed?(sandbox, "/project2/secret")
    end

    test "returns true for root itself", %{sandbox: sandbox} do
      assert Sandbox.path_allowed?(sandbox, "/project")
    end

    test "handles trailing slashes (DomePath behavior)", %{sandbox: sandbox} do
      assert Sandbox.path_allowed?(sandbox, "/project/")
      assert Sandbox.path_allowed?(sandbox, "/libs/")
    end
  end

  describe "path_allowed?/2 - path traversal attacks" do
    setup do
      {:ok, sandbox} = Sandbox.new(["/project"], "/project")
      %{sandbox: sandbox}
    end

    test "rejects .. traversal that escapes sandbox", %{sandbox: sandbox} do
      # /project/../etc/passwd should resolve to /etc/passwd - OUTSIDE sandbox
      refute Sandbox.path_allowed?(sandbox, "/project/../etc/passwd")
    end

    test "rejects multiple .. traversals", %{sandbox: sandbox} do
      # /project/src/../../etc/passwd -> /etc/passwd
      refute Sandbox.path_allowed?(sandbox, "/project/src/../../etc/passwd")
    end

    test "allows .. that stays within sandbox", %{sandbox: sandbox} do
      # /project/src/../lib/file.ex -> /project/lib/file.ex - still inside
      assert Sandbox.path_allowed?(sandbox, "/project/src/../lib/file.ex")
    end

    test "rejects .. at end that escapes", %{sandbox: sandbox} do
      # /project/.. -> / (parent of project)
      refute Sandbox.path_allowed?(sandbox, "/project/..")
    end

    test "allows .. to root itself", %{sandbox: sandbox} do
      # /project/src/.. -> /project - still valid (is root)
      assert Sandbox.path_allowed?(sandbox, "/project/src/..")
    end
  end

  describe "path_allowed?/2 - caller must expand relative paths" do
    # path_allowed? now requires absolute paths - callers expand relative paths
    # using DomePath.expand(path, base) where base is home_path or current_path

    setup do
      {:ok, sandbox} = Sandbox.new(["/project"], "/project/src")
      %{sandbox: sandbox}
    end

    test "raises ArgumentError for relative path", %{sandbox: sandbox} do
      # Relative paths must be expanded by caller BEFORE calling path_allowed?
      # Silently accepting them would expand against CWD which may be outside sandbox
      assert_raise ArgumentError, ~r/path must be absolute/, fn ->
        Sandbox.path_allowed?(sandbox, "file.ex")
      end
    end

    test "raises ArgumentError for dot-relative path", %{sandbox: sandbox} do
      assert_raise ArgumentError, ~r/path must be absolute/, fn ->
        Sandbox.path_allowed?(sandbox, "./file.ex")
      end
    end

    test "raises ArgumentError for parent-relative path", %{sandbox: sandbox} do
      assert_raise ArgumentError, ~r/path must be absolute/, fn ->
        Sandbox.path_allowed?(sandbox, "../etc/passwd")
      end
    end

    test "absolute path in sandbox is allowed", %{sandbox: sandbox} do
      # Caller expanded "file.ex" against home_path "/project/src"
      assert Sandbox.path_allowed?(sandbox, "/project/src/file.ex")
    end

    test "absolute path with subdir is allowed", %{sandbox: sandbox} do
      # Caller expanded "lib/foo.ex" against home_path "/project/src"
      assert Sandbox.path_allowed?(sandbox, "/project/src/lib/foo.ex")
    end

    test "absolute path at root level is allowed", %{sandbox: sandbox} do
      # Caller expanded "../README.md" against "/project/src" -> "/project/README.md"
      assert Sandbox.path_allowed?(sandbox, "/project/README.md")
    end

    test "absolute path outside sandbox is rejected", %{sandbox: sandbox} do
      # Caller expanded "../../etc/passwd" against "/project/src" -> "/etc/passwd"
      refute Sandbox.path_allowed?(sandbox, "/etc/passwd")
    end
  end

  describe "new/2 - path canonicalization" do
    test "canonicalizes allowed_paths with .. segments" do
      # Path with .. should be canonicalized
      {:ok, sandbox} = Sandbox.new(["/project/../project"], "/project")
      # The stored allowed_path should be canonical
      assert sandbox.allowed_paths == ["/project"]
    end

    test "canonicalizes home_path with .. segments" do
      {:ok, sandbox} = Sandbox.new(["/project"], "/project/src/../lib")
      # The stored home_path should be canonical
      assert sandbox.home_path == "/project/lib"
    end

    test "canonicalizes multiple allowed_paths" do
      {:ok, sandbox} = Sandbox.new(["/a/../b", "/c/d/../e"], "/b")
      assert "/b" in sandbox.allowed_paths
      assert "/c/e" in sandbox.allowed_paths
    end
  end

  describe "validate/1" do
    test "returns ok for valid sandbox" do
      sandbox = %Sandbox{allowed_paths: ["/project"], home_path: "/project"}
      assert {:ok, ^sandbox} = Sandbox.validate(sandbox)
    end

    test "returns error for empty allowed_paths" do
      sandbox = %Sandbox{allowed_paths: [], home_path: "/project"}
      assert {:error, _} = Sandbox.validate(sandbox)
    end

    test "returns error for home_path outside allowed_paths" do
      sandbox = %Sandbox{allowed_paths: ["/project"], home_path: "/elsewhere"}
      assert {:error, _} = Sandbox.validate(sandbox)
    end
  end
end
