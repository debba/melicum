# System volume device

The driver wraps BlackHole from https://github.com/ExistentialAudio/BlackHole at commit `561d934c77a1fa64987e01ccabe890fed30e181f`.

The upstream source is preserved in `ThirdParty/BlackHole`. It is licensed under GPL-3.0; the source license is included there. This application is GPL-3.0. The upstream name, icon and branding are not used for the modified device or installer.

`SystemVolume.c` configures a stereo output-only device, adds a private owner heartbeat and exposes the standard volume and mute controls to macOS. Its input stream and hidden mirror streams are disabled. The app captures per-process output targeted at this device and forwards it to a physical output; the loopback volume code is not used. The app reads the device's scalar/mute properties and applies gain in its real-time processor. This avoids applying volume twice.

The device starts unavailable. The device is named Melicum. The app marks it available before building the audio path and keeps it alive with a one-second heartbeat. When the heartbeat expires or the owner process exits, the device becomes unavailable and macOS can fall back to another output. Normal shutdown restores the previous physical output before removing the heartbeat.
