# SubPop share destination

`SubPop.fcpxdest` is the unmodified destination exported by Final Cut Pro
Creator Studio 12.4 (build 454072) through the Destinations UI on 2026-10-10.
The UI configuration was **Export File → Audio Only → WAV → Open With SubPop**.
Its display name is **发送到 SubPop**. The temporary authoring destination was
removed after export; no user projects were included.

SHA-256: `3481e4d53c567e0d3fdc341bd7fd6eec2b822354dff8ee04446cfd7c1f16e475`

The archive contains a fixed `/Applications/SubPop.app` application target,
which matches the package's installation location. It contains no application
bookmark, user home path, volume identity, project, source media, or credential.
The destination UUID is its own stable preset identity, not a project or machine
identity. The host FCP application is not hard-coded into the preset.

The WAV encoder enables audio and disables video; no role preset is selected.
FCP's `exportInOutRangeOnly` value is preserved as exported. Users must share the
complete active project; SubPop verifies project identity and complete duration
before accepting the audio. The archive is not edited to guess undocumented
behavior, and its generic codec description is not interpreted as the selected
format.

The signed package installs this resource through the main application's narrow
installer command. It creates `SubPop.fcpxdest` in the system Share Destinations
directory without replacing an existing different file. The application's repair
action can safely add the same preset to the current user's Share Destinations
directory, but avoids a duplicate when the identical system preset exists.
Filesystem installation does not claim that a running FCP has loaded it; FCP
loading and end-to-end sharing require separate host acceptance.

Apple documents exporting and distributing `.fcpxdest` files and the system and
user installation directories in [Receiving Media and Data Through a Custom
Share Destination](https://developer.apple.com/documentation/professional-video-applications/receiving-media-and-data-through-a-custom-share-destination).
