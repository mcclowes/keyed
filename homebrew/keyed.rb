cask "keyed" do
  version :latest
  sha256 :no_check
  url "https://github.com/mcclowes/keyed/releases/latest/download/Keyed.zip"
  name "Keyed"
  desc "Native macOS text expansion tool"
  homepage "https://github.com/mcclowes/keyed"

  depends_on macos: ">= :sonoma"

  app "Keyed.app"

  zap trash: [
    "~/Library/Application Support/Keyed",
    "~/Library/Preferences/com.mcclowes.keyed.plist",
  ]
end
