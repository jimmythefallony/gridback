# Backlog

Recorded only. None of these are in progress.

- Dragging along the edge of a row still shifts the icon under the pointer before a folder hold can finish. Revisit after the current folder work.
- Drag an app from the grid onto the real macOS Dock.
- Measure grid-opening time on a cold launch and a warm launch, plus CPU and memory while the grid is idle and while it is open. Change performance only from those measurements.
- Escape during a drag is still unresolved. A timer that polled the event queue with `nextEvent` was removed after it was reported to freeze every drag. Do not put that polling back.
