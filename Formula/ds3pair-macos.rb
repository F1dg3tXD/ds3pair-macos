class Ds3pairMacos < Formula
  desc "DualShock 3 pairing and diagnostic utility for macOS"
  homepage "https://github.com/F1dg3tXD/ds3pair-macos"
  url "https://github.com/F1dg3tXD/ds3pair-macos/archive/refs/tags/v0.0.3a.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  license "MIT"

  depends_on :xcode

  def install
    system "swift", "build",
           "--configuration", "release"

    bin.install ".build/release/ds3pair-macos"
  end

  test do
    system "#{bin}/ds3pair-macos", "--version"
  end
end
