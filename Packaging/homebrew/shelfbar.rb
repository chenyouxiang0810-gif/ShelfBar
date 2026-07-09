cask "shelfbar" do
  version "1.0.0-beta.1"
  sha256 "44ccc084e23aee29fa6c1064564e548201e35bd7eb88847b0c77169cb4f41c6f"

  url "https://github.com/chenyouxiang0810-gif/ShelfBar/releases/download/v#{version}/ShelfBar.dmg"
  name "ShelfBar"
  desc "Turn your MacBook Touch Bar into a smart file shelf"
  homepage "https://github.com/chenyouxiang0810-gif/ShelfBar"

  depends_on macos: ">= :sequoia"

  app "ShelfBar.app"

  caveats do
    <<~EOS
      ShelfBar requires an Intel Mac with a physical Touch Bar.

      This beta may require System Settings > Privacy & Security > Open Anyway
      until the app is Developer ID signed and notarized.
    EOS
  end
end
