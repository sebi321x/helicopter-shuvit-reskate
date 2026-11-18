# Helicopter Shuvit for ReSkate

**Hold a pop shuvit and hover like a helicopter.** Let the board spin a little longer to clear a gap. Release it to drop back in, or start a late shuvit on the way down to catch yourself. Nollies work too.

[Download the v0.4.1 beta for offline free skate](https://github.com/sebi321x/helicopter-shuvit-reskate/releases/download/v0.4.1/Helicopter_Shove_It-0.4.1-runtime.zip)

## Install

This beta uses a modified ReSkate **20261116** runtime to control lift. The download includes the plugin and the matching DLL.

1. Close ReSkate. Back up the original `ReSkate.dll` next to `Skate.exe`.
2. Copy `runtime/ReSkate.dll` from the ZIP into that location. Copy the entire `Helicopter_Shove_It` folder into `Mods`.
3. In the ReSkate launcher, turn off **Install ReSkate updates** so the launcher keeps the matching runtime. Launch normally. For a single session, the `--no-update` launch option also works.
4. Start offline free skate and choose **Turn on** when prompted.

## Dial in the flight

Open **Insert → Plugins → Helicopter Shove It**. Set **Target vertical speed** to zero to hover, above zero to climb, or below zero for a gentler fall. Adjust the start angle and lift curve to choose how much spin it takes to feel the pull. Both directions can lift, or you can assign one to lift and the other to dive.

To uninstall, remove the plugin folder, restore your backed-up DLL, and turn launcher updates back on.

[Runtime source and build instructions](source/README.md)
