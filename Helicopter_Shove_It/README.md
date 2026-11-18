# Helicopter Shove It

Hold a pop shove-it and the board starts to lift. Give yourself a little more time to catch it or keep spinning and climb. Let go to drop back in. If you're still in the air, spin it up again.

Works in offline free skate with frontside, backside, 360, and nollie pop shove-its. In **Insert → Plugins → Helicopter Shove It**, set **Target vertical speed** to zero to hover, a positive value to climb, or a negative value for a slower fall. Pick **Both directions**, or pick one side for lift and use the other for a dive. The start angle and curve keep ordinary shove-its feeling ordinary.

## Manual-install beta

Flight needs the companion ReSkate runtime based on build **20261116**. Stock ReSkate runs the rotor sound. The companion runtime must be installed separately before the board can lift or dive.

1. Close ReSkate and keep a copy of your original `ReSkate.dll`.
2. Place the companion `ReSkate.dll` from the `runtime` folder next to `Skate.exe`. Put the `Helicopter_Shove_It` folder in `Mods`.
3. In the ReSkate launcher settings, turn off **Install ReSkate updates** while using the companion runtime. For a one-time launch, use `--no-update`.
4. Open an offline session and choose **Turn on** when ReSkate asks about the plugin.

**Log jumps for tuning** is off by default. If enabled, it records in-game motion and trick names in the local ReSkate log.
