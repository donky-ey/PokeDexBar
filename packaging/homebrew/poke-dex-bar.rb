cask "poke-dex-bar" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/donky-ey/PokeDexBar/releases/download/v#{version}/PokeDexBar.zip"
  name "PokeDexBar"
  desc "Menu bar app turning AI coding token usage into a Pokemon collection"
  homepage "https://github.com/donky-ey/PokeDexBar"

  depends_on macos: :sonoma

  app "PokeDexBar.app"

  zap trash: [
    "~/Library/Application Support/PokeDexBar",
    "~/Library/Preferences/io.github.donky-ey.pokedexbar.plist",
    "~/Library/Logs/PokeDexBar.log",
    "~/Library/Logs/PokeDexBar.old.log",
    "~/Library/Logs/PokeDexBar.crash.log",
    "~/Library/Logs/PokeDexBar.running",
  ]
end
