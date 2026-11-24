# Changelog

## Unreleased

- After a folder is allowed, the first time the grid opens it shows the blurred wallpaper.
- Settings shows whether GridBack can read the wallpaper's folder, and what to do next.
- GridBack asks once, in a small window, before it opens a wallpaper in Desktop, Documents, Downloads, or on a removable disk. The window is visible on every Space. If macOS has already refused that folder, the plain fallback stays. An iCloud Drive image is opened only when it is already on this Mac. A shortcut pressed while the system folder prompt is open is ignored.
- Groundwork for asking permission to show wallpapers from private folders.
- Idle CPU in the open summary uses gaps of a minute or longer. Each open records how long the grid stayed closed, and the average over every gap is still shown.
- A colour you pick yourself in Wallpaper settings is matched, with dark or light text so it stays readable.
- An Aerial desktop shows a blurred frame of that scene. A Shuffle or time-of-day Aerial updates the next time the grid opens.
- GridBack writes how fast the grid opened, and the CPU and memory around that open, to this Mac's log.

## v0.3.7 (2026-11-18)

- The plain fallback background follows Light and Dark: pale grey with dark text in Light, charcoal in Dark, and it fades across when you switch.
- Command-A, C, V, X, Z, Undo and Redo work in search.
- Search holds up to 100 characters, and pasted text is tidied onto one line.
- Press Command-Q twice to quit. A short note appears on the first press.
- Pressing Command-Q twice matches the Q you type, so it works on a French keyboard and other layouts.
- Labels, page dots and search text are now readable on light and mid-tone solid-colour wallpapers.
