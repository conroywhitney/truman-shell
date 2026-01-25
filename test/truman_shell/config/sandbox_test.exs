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
    test "succeeds when default_cwd equals root" do
      assert {:ok, sandbox} = Sandbox.new(["/project"], "/project")
      assert sandbox.roots == ["/project"]
      assert sandbox.default_cwd == "/project"
    end

    test "succeeds when default_cwd is subdirectory of root" do
      assert {:ok, sandbox} = Sandbox.new(["/project"], "/project/src")
      assert sandbox.default_cwd == "/project/src"
    end

    test "fails when default_cwd is outside root" do
      assert {:error, msg} = Sandbox.new(["/project"], "/elsewhere")
      assert msg =~ "default_cwd must be within one of the roots"
    end

    test "fails when roots list is empty" do
      assert {:error, msg} = Sandbox.new([], "/project")
      assert msg =~ "at least one root"
    end
  end

  describe "new/2 - multiple roots" do
    test "succeeds when default_cwd is in any root" do
      roots = ["/project", "/libs"]
      assert {:ok, sandbox} = Sandbox.new(roots, "/libs")
      assert sandbox.default_cwd == "/libs"
    end

    test "succeeds when default_cwd is subdirectory of second root" do
      roots = ["/project", "/libs"]
      assert {:ok, sandbox} = Sandbox.new(roots, "/libs/elixir")
      assert sandbox.default_cwd == "/libs/elixir"
    end

    test "fails when default_cwd is outside all roots" do
      roots = ["/project", "/libs"]
      assert {:error, _} = Sandbox.new(roots, "/tmp")
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
      assert sandbox.default_cwd == "/project/a/b/c/d/e"
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

    test "returns false for path outside all roots", %{sandbox: sandbox} do
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

  describe "validate/1" do
    test "returns ok for valid sandbox" do
      sandbox = %Sandbox{roots: ["/project"], default_cwd: "/project"}
      assert {:ok, ^sandbox} = Sandbox.validate(sandbox)
    end

    test "returns error for empty roots" do
      sandbox = %Sandbox{roots: [], default_cwd: "/project"}
      assert {:error, _} = Sandbox.validate(sandbox)
    end

    test "returns error for cwd outside roots" do
      sandbox = %Sandbox{roots: ["/project"], default_cwd: "/elsewhere"}
      assert {:error, _} = Sandbox.validate(sandbox)
    end
  end
end
