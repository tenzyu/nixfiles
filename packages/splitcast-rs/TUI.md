# Select routes in the terminal

The terminal menu uses line mode. Enter a displayed number and press Enter. It also accepts piped input.

1. Use **1 Refresh** to inspect the agent's route table and current selections.
2. Use **2 Discover** to list exact capture targets, game applications, raw microphones, TTS sinks, and stable camera devices.
3. While the session is Idle, use **3 Select route settings** to choose a field and a numbered value. Each selection saves immediately through the agent. Stop the session before changing another running route.
4. Use **4 Doctor** to check prerequisites.
5. Use **6 Start RECORDING** to start recording. **5 Prepare** is optional when starting from Idle.
6. Use **7 Stop** to stop the session explicitly.

The route table comes from the agent. Route templates keep game capture, microphone processing, camera transport, TTS, and overlay connections fixed. The menu does not create arbitrary connections or change local audio defaults.

**13 Twitch** is separate from recording and requires the full word `TWITCH`. No action retries or switches to Twitch automatically.

**9 Microphone**, **10 TTS**, **11 Overlay text**, and **12 Say text** send explicit commands. The agent validates text limits and session readiness. **8 Preview info** requests a preview but does not display or save its image in line mode.

**0 Quit** or end-of-input closes the menu without changing the session. An unfinished line does not execute. The menu does not enter raw mode or write credentials. Unsupported discovery responses produce no selectable devices.
