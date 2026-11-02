# GridBack

GridBack is a free menu-bar app for Mac. It opens a full-screen grid of the apps on your Mac, so you can see them, arrange them yourself, and click one to open it.

It is a Launchpad replacement for people who liked that familiar grid. It is built for Apple Silicon Macs running **macOS 26 or later**.

GridBack v0.1 is an early open-source build. It is **unsigned**. macOS will warn you before it opens. That warning is expected.

## Open an unsigned copy

Use this when you downloaded GridBack (a `.zip` from GitHub) instead of running it from Xcode.

1. Unzip the download if your browser did not do that already.
2. Move **GridBack** into your Applications folder if you want it to stay there. You can also leave it in Downloads while you try it.
3. Double-click **GridBack**. macOS tells you it could not verify the app, and it does not open.
4. Open **System Settings → Privacy & Security**.
5. Scroll to the Security section. Find the note that GridBack was blocked and click **Open Anyway**, then **Open**.

If you do not see **Open Anyway**:

1. In Finder, **Control-click** GridBack.
2. Choose **Open**.
3. In the dialog, choose **Open** again.

If macOS still refuses, and you are comfortable with Terminal, this clears the download quarantine flag on that one app:

```bash
xattr -dr com.apple.quarantine /Applications/GridBack.app
```

Then try opening it again. You only need this for a downloaded copy. Running from Xcode does not show this warning.

## Run it from Xcode

You need an Apple Silicon Mac, macOS 26 or later, and Xcode that includes the macOS 26 SDK. A paid Apple Developer account is not required.

1. Install **Xcode** from the App Store. Open it once and let it install any extra components it asks for.
2. Download this project and unzip it, or clone the repository.
3. Double-click **`GridBack.xcodeproj`**. That is the blue Xcode icon. Open that file, not `Package.swift`.
4. At the top of the window, next to the Run button, set the destination to **My Mac**. Leave the scheme set to **GridBack**.
5. Press **Run** (the play button), or press **Command-R**.
6. The first build can take a minute. When it finishes, look in the **menu bar** at the top of the screen for a grid icon (a small 3×3 of squares).
7. Click that icon. You should see **Open GridBack**, **Settings…**, the current shortcut, and **Quit GridBack**.
8. Choose **Open GridBack**. A dark grid of your apps covers the main display.

The project is set to build for Apple Silicon only (`arm64`) and macOS 26.0 or later. Xcode may ad-hoc sign the copy it runs so your Mac will open it. That is separate from the unsigned zip used for a GitHub Release.

### The keyboard shortcut

The starting shortcut is **Control-Option-G** (hold Control and Option, then press G). It opens the grid, and the same shortcut closes it.

GridBack registers that shortcut with macOS. It does **not** ask for Accessibility access. If another app already owns that key combination, registration fails. The menu bar menu then says the shortcut is not available, and **Open GridBack** still works. Choose **Settings…**, click **Change Shortcut**, and press a combination that includes Control, Option, or Command. Escape cancels recording.

To quit, click the menu bar icon and choose **Quit GridBack**.

## What you should see (v0.1)

Try these on your Mac after the app is running. The automated tests on this project check ordering, search, and saving. They do not open the window, so these steps are the real check.

1. **It builds and the menu bar icon appears.** Xcode’s Run finishes, and the grid icon is in the menu bar.
2. **Quit and open again.** Arrange two apps, quit from the menu bar, run the app again from Xcode, and open the grid. Those two apps are still in the order you left them.
3. **The shortcut opens and closes the grid.** Control-Option-G, or whatever you set in Settings. The menu shows the shortcut that is active.
4. **One display only.** The grid covers the display macOS treats as the main display (the one at the top-left of the arrangement in System Settings → Displays). With a second display connected, the grid does not also appear over there.
5. **The apps are the ones in your Applications folders.** You should see apps from `/Applications`, `/System/Applications`, and your home `Applications` folder, including folders such as Utilities. You should not see helper tools buried inside another app, hidden items, or background-only agents. If two copies share one bundle id, GridBack keeps the one in your home Applications folder first, then `/Applications`, then the System folder.
6. **Click an app.** It opens or comes to the front, and the grid closes. If the app cannot be opened, the grid stays up and a short message appears.
7. **Type to search.** With the grid open, type part of an app’s name. The grid filters. Upper and lower case do not matter. Press Return to open the highlighted app. Press Escape once to clear the search and show the full grid again. Press Escape again to close the grid. Arrow keys move through search results. Left and right arrows change pages when you are not searching.
8. **Drag to rearrange.** Drag an icon to a new spot on the page. The gap closes on that page. Apps on the next page stay on the next page. Drop an icon on the arrow at the side of the screen to move it to the neighboring page. Quit, run the app again, and the new order is still there.
9. **An unsigned download warns, then runs.** On a Mac, run `scripts/package-unsigned.sh` (instructions below). Unzip the result, open it, and expect the Gatekeeper warning above. After you allow it, the menu bar icon appears and the grid opens.

Clicking empty space on the grid closes it. A brand new install lines apps up by name (numbers sort in numeric order, so “App 2” comes before “App 10”). After you arrange them, new apps are added at the end. GridBack does not shuffle the whole grid again.

Your layout and shortcut are saved on this Mac only, in:

`~/Library/Application Support/GridBack/state.json`

There is no account, no telemetry, and no crash reporter.

## What v0.1 includes

- A menu bar icon with Open, Settings, and Quit
- A configurable keyboard shortcut
- A full-screen-style grid on the primary display, with pages and page dots
- Click to open an app
- Type to search
- Drag to rearrange, with the order saved on this Mac
- An unsigned build script for a later GitHub Release

## What v0.1 leaves for later

| Version | What it is for |
| --- | --- |
| **v0.1** (this one) | Menu bar, shortcut, grid, search, launch, drag, saved layout, unsigned download |
| **v0.2** | Folders: create, rename, and move apps into them |
| **v0.3** | Trackpad pinch, after a small experiment to see if it can work cleanly |
| **Later** | Signed and notarized builds, automatic updates, Homebrew, optional crash reports |

Trackpad pinch and folders are not in this version. GridBack does not import an old Launchpad layout.

## Make an unsigned download (on a Mac)

After the app has been tried in Xcode:

```bash
./scripts/package-unsigned.sh
```

The script writes `build/GridBack-0.1.0-unsigned-arm64.zip` and a `.sha256` checksum next to it. Those files are what you attach to a GitHub Release, with a short note that the app is unsigned and early. The script has to run on a Mac. It was not run in the environment that first added this project.

## For people who want the product notes

- [Product one-pager](docs/PRD-onepager.md)
- [v0.1 build plan](docs/v0.1-build-plan.md)

The logic tests (ordering, search, catalog rules, and the saved file) run with:

```bash
swift test
```

They do not launch the Mac app.

## License

GridBack is released under the [MIT License](LICENSE). Copyright 2026 jimmythefallony.
