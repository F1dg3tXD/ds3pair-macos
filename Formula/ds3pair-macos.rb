class Ds3pairMacos < Formula
  desc "DualShock 3 pairing and diagnostic utility for macOS"
  homepage "https://github.com/F1dg3tXD/ds3pair-macos"
  url "https://github.com/F1dg3tXD/ds3pair-macos/archive/refs/tags/v0.0.4a.tar.gz"
  sha256 "e3af582b3eceba4e5bf033bb01a42702d04d20776f92ce4c97c91c84e8ece24d"
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
