# SubPop share destination

`发送到 SubPop.fcpxdest` is the unmodified destination exported by Final Cut Pro
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
installer command. It creates `发送到 SubPop.fcpxdest` in the system Share Destinations
directory without replacing an existing different file. The application's repair
action can safely add the same preset to the current user's Share Destinations
directory, but avoids a duplicate when the identical system preset exists.
Filesystem installation does not claim that a running FCP has loaded it; FCP
loading and end-to-end sharing require separate host acceptance.

Apple documents exporting and distributing `.fcpxdest` files and the system and
user installation directories in [Receiving Media and Data Through a Custom
Share Destination](https://developer.apple.com/documentation/professional-video-applications/receiving-media-and-data-through-a-custom-share-destination).

In the 1.5.10 live check, Final Cut Pro displayed the installed filename stem
`SubPop`, despite the archive's original display name. The original FCP-exported
filename is therefore preserved. An upgrade migrates
only the fixed legacy `SubPop.fcpxdest` when it is a safe regular file with the
exact pinned bytes above. Different contents are preserved as a conflict;
arbitrarily renamed destinations are not renamed or removed. The ordinary app
never changes a legacy system preset: it asks the user to install the newer
package, and does not create a duplicate user copy.

Migration first isolates the old name and revalidates the acquired file, so a
concurrent FCP save is not deleted on the strength of an earlier hash check.
Rollback never overwrites a concurrent file; if its original name is occupied,
the error reports the retained `.SubPop-legacy-…` path. System installation only
migrates the system directory. An existing current-user legacy copy is handled
on the next explicit repair, without scanning other users' configuration.
