class Macp < Formula
  desc "Give Claude Code the ability to operate and debug macOS apps"
  homepage "https://github.com/xiao99xiao/macp"
  url "https://github.com/xiao99xiao/macp.git", tag: "0.1.0"
  license "MIT"
  head "https://github.com/xiao99xiao/macp.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/macp"
  end

  def caveats
    <<~EOS
      To use macp with Claude Code, install the skill:
        macp install-skill

      macp requires macOS permissions. Grant them to your terminal app:
        System Settings > Privacy & Security > Accessibility
        System Settings > Privacy & Security > Screen Recording

      Verify with:
        macp check-access
    EOS
  end

  test do
    assert_match "Mac App Control Protocol", shell_output("#{bin}/macp --help")
  end
end
