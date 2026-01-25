# Skip platform-specific tests
exclude =
  case :os.type() do
    {:unix, :linux} -> [:skip_on_linux]
    {:unix, :darwin} -> [:skip_on_macos]
    _ -> []
  end

ExUnit.start(exclude: exclude)
