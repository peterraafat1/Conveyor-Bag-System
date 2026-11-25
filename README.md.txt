# Conveyor Bag System (Roblox / Luau)

A small server-authoritative conveyor for Roblox. The server decides when bags spawn and how long they live. Clients draw the bags and tween them along the belt using the server's timestamp, so every player sees the same thing. One player at a time (the "controller") can change the spawn interval with an on-screen slider.

## What it does

- Spawns a bag on a fixed schedule (default every 1.0 s, adjustable from 0.1 s to 5.0 s) with a random colour and material. Up to 30 bags at once.
- Each bag lives about 0.5 s (spawn), 5 s (travel, 50 studs at 10 studs/s) and 0.3 s (despawn).
- Clients animate bags with `TweenService`. Players who join late ask the server for a snapshot and draw the bags in the correct position.
- The first player in the server becomes the interval controller and receives the control panel. If that player leaves, the next player takes over.
- Clicking a bag sends its id to the server. The server accepts it only if the id is a short string, the bag exists and is still alive, the player's character is within 14 studs of the bag's computed position, and the player is not clicking faster than every 0.2 s. The prototype only logs the click and grants no reward.
- Interval changes are validated on the server (must be a number between 0.1 and 5.0), rate limited, rounded to 0.1 s, and echoed back so the UI shows the server's value.

## Files

| File | Type | Where to put it in Studio |
| --- | --- | --- |
| `src/ConveyorServer.server.lua` | Script | ServerScriptService |
| `src/BagVisuals.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
| `src/IntervalSlider.client.lua` | LocalScript | Inside the ControlPanel ScreenGui (see below) |

## Setup in Roblox Studio

1. Add the three scripts from `src/` in the places listed above.
2. Build the control panel. The code requires this structure and these exact names:
   - A `ScreenGui` named `ControlPanel` in `ServerStorage`. The server script waits for it, so the server script does not continue past that line if it is missing.
   - Inside it: `IntervalSlider.client.lua` (as a LocalScript, a direct child of the ScreenGui) and a `Frame` named `Frame`.
   - Inside `Frame`: a GUI object named `SliderButton` (it listens for mouse and touch input, for example a `TextButton`) and a `TextLabel` named `IntervalText`.
   - The slider moves `SliderButton` horizontally inside `Frame`, so give `Frame` a width larger than the button. Size, colours and position are free to choose.
3. Press Play. Bags run from (0, 5, 0) to (0, 5, 50). The belt itself is not created by the scripts, so add your own belt model along that line if you want one.

The server script creates the RemoteEvents it needs (`ChangeInterval`, `SpawnBag`, `BagClicked`, `BagSnapshot`, `RequestBagSnapshot`, `RequestIntervalState`, `IntervalState`) in `ReplicatedStorage > Shared > Remotes`.

## Settings

Constants at the top of `ConveyorServer.server.lua`: `MAX_BAGS`, `MIN_INTERVAL`, `MAX_INTERVAL`, `CONVEYOR_START`, `CONVEYOR_END`, `CONVEYOR_SPEED`, and the `timings` table.

## Limitations

- The belt path is a straight line and is hard-coded in the server and client scripts; there are no curves or branches.
- The click handler does not give rewards. It is a validation example.
- No automated tests are included yet.
- Bags are not physics objects; their position is computed from time.
