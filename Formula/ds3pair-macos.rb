class Ds3pairMacos < Formula
  desc "DualShock 3 pairing and diagnostic utility for macOS"
  homepage "https://github.com/F1dg3tXD/ds3pair-macos"
  url "https://github.com/F1dg3tXD/ds3pair-macos/archive/refs/tags/v0.0.4a.tar.gz"
  sha256 "f2426d3b806f56587b23b9f4ab6fb3cb57acb34c2c1c730968f776984c9d6a6e"
  license "MIT"

  depends_on :xcode

  def install
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox"

    bin.install ".build/release/ds3pair-macos"
  end

  test do
    system "#{bin}/ds3pair-macos", "--version"
  end
end
