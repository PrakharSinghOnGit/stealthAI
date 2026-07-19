unzip ./dist/stealthAI-macos.zip

# close if running
osascript -e 'quit app "stealthAI"' || true

rm -rf /Applications/stealthAI.app
mv stealthAI.app /Applications/

xattr -dr com.apple.quarantine /Applications/stealthAI.app
codesign --force --deep --sign - /Applications/stealthAI.app
open /Applications/stealthAI.app

