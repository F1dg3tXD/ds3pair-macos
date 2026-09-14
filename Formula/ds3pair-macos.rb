class Ds3pairMacos < Formula
  desc "DualShock 3 pairing and diagnostic utility for macOS"
  homepage "https://github.com/F1dg3tXD/ds3pair-macos"
  url "https://github.com/F1dg3tXD/ds3pair-macos/archive/refs/tags/v0.0.4b.tar.gz"
  sha256 "2f518c176d664e953568916f18005d4449fae8845489cd80f7749d6f6f29a432"
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
