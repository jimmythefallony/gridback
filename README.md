# GridBack

**A free, open-source replacement for the classic macOS Launchpad.**

GridBack is a free menu-bar app for Mac. It opens a full-screen grid of your apps, so you can see them, keep them in the order you like, and click one to open it.

This is an early release, version 0.1.0. It is open source, and it is not a finished product.

## What works

These were checked on a real Mac running macOS 27, built with Xcode 27.2.

- A grid icon sits in the menu bar. Click it for **Open GridBack**, **Settings…**, and **Quit GridBack**.
- The shortcut is **Control-Option-G**. It works while another app is in front. The same shortcut closes the grid. You can change it in Settings.
- Type to search for an app.
- Escape clears the search. Press Escape again and the grid closes.
- Click an app to open it.
- Drag apps to rearrange them. The new order is still there after you quit and open GridBack again.
- Drag an app to the left or right edge of the screen to move it to another page.
- Change pages with a two-finger swipe on the trackpad, the left and right arrow keys, or the arrows on the screen.
- The grid can open on top of an app that is in full screen.
- GridBack remembers the page you were on.
- If you have another monitor connected, the grid appears on the main display.

## What this version does not do

Folders are not in this version, and neither is the pinch gesture on the trackpad. The Dock does not show over the grid. These are planned for a later version.

The app is unsigned and not notarized. macOS will warn you the first time you open a downloaded copy. That is expected. See below.

## What you need

An Apple silicon Mac running **macOS 26 or later**. That is the minimum set in the Xcode project. The app is built for Apple silicon only.

## Install

1. Open the [GitHub Releases](https://github.com/jimmythefallony/gridback/releases) page for this project and download **GridBack-v0.1.0.zip**.
2. Unzip it.
3. Move **GridBack.app** into your Applications folder.

The first time you open it, macOS says it cannot verify the developer. GridBack is free and open source, and it is not signed with a paid Apple developer certificate. macOS shows that warning for apps like this.

On current macOS, including macOS 26 and 27, Apple’s own steps are:

1. Try to open GridBack. When the warning appears, close it. Leave the app where it is.
2. Open the Apple menu and choose **System Settings**.
3. Click **Privacy & Security** in the sidebar. You may need to scroll to find it.
4. Scroll down to **Security** and click **Open Anyway**. macOS shows that button for about an hour after you tried to open the app. If it is not there, open GridBack once more, close the warning, and come straight back to this screen.
5. The warning appears again. Click **Open**.
6. Enter your Mac login password and click **OK**.

After that, you can open GridBack by double-clicking it, the same as any other app.

You can also try a right-click (or Control-click) on the app, choose **Open**, then **Open** again. On current macOS that choice is often not offered for an app that is not signed and notarized. If you do not see it, use **Privacy & Security** as above. These steps follow Apple’s guide, [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

## Build it yourself

You need an Apple silicon Mac with macOS 26 or later, and Xcode.

1. Download this project and unzip it, or clone the repository.
2. Double-click **GridBack.xcodeproj**.
3. At the top of Xcode, set the destination to **My Mac**.
4. Press **Run** (the play button).

The copy that was checked for this release was built with Xcode 27.2.

## Tell us what happened

If something does not work the way you expected, open an issue:

https://github.com/jimmythefallony/gridback/issues

Please include your macOS version, what you expected, and what happened instead.

## What comes next

Version 0.2 will add folders, and we will refine the app from what testers report.

## License

GridBack is released under the [MIT License](LICENSE). Copyright 2026 jimmythefallony.
