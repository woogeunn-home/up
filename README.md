# Up

Up is a macOS SwiftUI app that reminds you to stand up after continuous computer use.

## What it does

- Default target time is 1 hour.
- The app checks macOS HID idle time once per second.
- If recent mouse or keyboard activity is detected, active time increases.
- When active time reaches the selected target, the app plays a sound and opens the menu bar popover.
- The app runs from the macOS menu bar.

## Project Structure

- `Up.xcodeproj`: Xcode project with the app target.
- `Up`: macOS SwiftUI menu bar app, timer, settings, and activity monitor.

## Before Distribution

Before signing or distributing, confirm these values match your Apple Developer team:

- `DEVELOPMENT_TEAM` for `Up`
- `PRODUCT_BUNDLE_IDENTIFIER` for `Up`: `com.woogeunn.Up`
