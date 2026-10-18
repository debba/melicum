# System volume device

The driver wraps BlackHole from https://github.com/ExistentialAudio/BlackHole at commit `561d934c77a1fa64987e01ccabe890fed30e181f`.

The upstream source is preserved in `ThirdParty/BlackHole`. It is licensed under GPL-3.0; the source license is included there. This application is GPL-3.0. The upstream name, icon and branding are not used for the modified device or installer.

`SystemVolume.c` configures a stereo output-only device, adds a private owner heartbeat and exposes the standard volume and mute controls to macOS. Its input stream and hidden mirror streams are disabled. The app captures per-process output targeted at this device and forwards it to a physical output; the loopback volume code is not used. The app reads the device's scalar/mute properties and applies gain in its real-time processor. This avoids applying volume twice.

The device starts hidden and unavailable. Before activating it, the app sends the selected physical output's name followed by ` (Melicum)` through a private CFString property, for example `DELL U2414H (Melicum)`. The driver exposes it through the standard read-only name property and notifies macOS when it changes; the device UID remains `HDMIAudioSystem_UID`. The app discovers it by that stable UID, makes it visible and available before building the audio path, and keeps it alive with a one-second heartbeat. Disabling audio or quitting restores the previous physical output before removing the heartbeat and hiding the virtual output from the macOS device list. When the heartbeat expires or the owner process exits, the device becomes hidden and unavailable so macOS can fall back to another output. The component remains installed without exposing an idle output.
