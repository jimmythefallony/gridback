# GridBack — Product Requirements One-Pager

**Working title:** GridBack  
**Date:** 2 November 2026  
**Audience:** Interviews, portfolio review, collaborators  
**Status:** Agreed product direction for a public open-source learning project  
**Author context:** Non-technical product manager shipping small open-source apps in public

---

## Problem

Apple removed classic Launchpad. People who relied on a visual, manually organized app grid now face a search-led workflow (Spotlight / Apple’s newer interface) that does not restore the familiar “see my apps, keep my layout, click to launch” habit.

## Target user

Mac users on **Apple Silicon** running **macOS 26+** who miss classic Launchpad: they want a free, local, native launcher that feels familiar, not a heavy commercial utility or a search-first replacement.

## Competition (verified facts only)

| Product | What was verified | Notes |
|--------|-------------------|--------|
| **Classic Apple Launchpad** | Behavioral reference on macOS 15 (owner’s reference Mac) | Removed / unavailable as the classic experience on macOS 26+ |
| **LaunchNext** | Free, open source ([github.com/RoversX/LaunchNext](https://github.com/RoversX/LaunchNext)); license file is **GPL-3.0** | Owner tested **v2.4.2**: pinch opens the launcher **and** Apple’s interface behind it; Escape dismisses Apple’s UI while LaunchNext stays visible (observed regression; root cause not established) |
| **LaunchOS** | Public site [launchosapp.com](https://launchosapp.com/) (as of 2 Nov 2026): **Free Basic** plan, **7-day Pro trial**, paid **Pro** lifetime licenses (**$11.99** / 1 device, **$18.99** / 2, **$35.99** / 5); many features labeled **Pro** (including trackpad gesture) | Feature-rich commercial alternative; GridBack is not aiming for full feature parity |

Do not treat marketing pages as proof of implementation quality.

## Positioning

**Free, native, open-source Launchpad replacement** for Apple Silicon / macOS 26+: small scope, ship fast, iterate in public. Familiar grid + manual organization first; polish and advanced integrations later. Working title only — final naming deferred.

## v0.1 scope (ship this first)

A **menu bar** macOS app that:

1. Starts quietly in the menu bar (Open / Settings / Quit recovery path).
2. Opens a **full-screen-style overlay** of installed apps on the **macOS-configured primary display** via a **configurable keyboard shortcut**.
3. **Click** an app to launch (via normal macOS launch APIs) and dismiss.
4. **Type to search** apps; clear/dismiss with expected keyboard behavior.
5. **Escape** closes the overlay (and clears search when appropriate).
6. **Drag to reorder** apps; layout **persists locally** across restarts.
7. Publishes an **unsigned** downloadable build via a **GitHub Release** (developer builds / Gatekeeper warnings expected until signing comes later).

### Explicit non-goals for v0.1

- Trackpad **pinch** / MultitouchSupport (planned after folders).
- **Folders**, nested organization, legacy Launchpad import.
- Sparkle updates, Homebrew cask, notarization / Developer ID signing.
- Telemetry, crash reporting, badges, hot corners, Dock integrations, multi-select, uninstall-other-apps, Intel / older macOS targets.

## Success metrics: outcomes, not vanity *(proposals only)*

Stars, download counts, and issue volume are **not** success metrics. They measure attention, not use. We may watch them, but no decision is based on them.

**Core question:** Do people who try it keep using it as their main way to open apps?

| Metric | What it tells us | How we measure it (v0.1 has no telemetry) |
|---|---|---|
| **Habit (north star):** share of testers still opening apps with it after 2 weeks | Whether it actually replaced Launchpad for them | Recruit 10–20 testers who miss Launchpad; check in at day 3, 7, and 14 |
| **Activation:** tester gets from download to first app launched without help | Whether onboarding and the unsigned-app warning are blockers | Watch 3–5 people install it live; note where they get stuck |
| **Frequency:** launches per day for active testers | Whether it's a daily tool or a novelty | Self-reported at check-ins; opt-in telemetry from a later version |
| **Switch reason:** why testers left their current workaround (Spotlight, Dock, LaunchNext) | Whether our positioning is real | One question at each check-in |
| **Churn reason:** why anyone stopped | What to build next | Short exit question; aim to have a reason for every tester who stops |

**Builder metrics (for the learning/portfolio goal):**
- Ship cadence: a tagged release roughly every 1–2 weeks.
- Feedback-to-fix time: days from a tester report to a released fix.
- A short public write-up per release covering what shipped, what we learned, and what changed.

**Proposed v0.1 bar:** at least half the testers are still using it at day 14, and every tester who drops off gives a reason we can act on. Targets are proposals to revisit after the first cohort.


## Recruiting testers (v0.1)

We'll find the first 10–20 testers in Reddit threads where people already say they miss Launchpad (for example r/MacOS and r/MacOSBeta posts about Launchpad's removal in macOS Tahoe).

1. Read each subreddit's self-promotion rules before posting, and follow them.
2. Lead with the problem and an honest ask: "I'm building a free, open-source Launchpad replacement and want 10–20 people to test v0.1 for two weeks." Link the GitHub release, and be upfront that it's unsigned and early.
3. Reply helpfully in existing "bring back Launchpad" threads instead of spamming new posts.
4. Collect testers through a short sign-up form, GitHub Discussions, or DMs, and note which workaround each person uses today.
5. Check in at day 3, 7 and 14 with the same three questions: Are you still using it? What made you open something else instead? What's missing?

## Key risks

1. **Pinch / private MultitouchSupport** — Deferred to later; still a roadmap risk (sandbox, stability, notarization, competing system UI). LaunchNext’s observed dual-UI pinch issue is a cautionary signal.
2. **GPL-3.0 if reusing LaunchNext code** — Verified LaunchNext LICENSE is GPL-3.0. Reuse would constrain GridBack’s license; prefer a **clean separate implementation** unless the owner explicitly accepts GPL obligations after a documented audit.
3. **Unsigned GitHub downloads** — macOS will warn / block; onboarding friction until signing/notarization.
4. **Primary-display / Spaces / focus** — Overlay must appear correctly over ordinary and full-screen apps without wrong Spaces behavior; needs real Mac QA.
5. **Working title / SEO / distribution** — Name, homepage, and Homebrew are later; early discovery may be limited.

## Roadmap

| Version | Focus |
|---------|--------|
| **v0.1** | Menu bar + shortcut overlay, search, launch, drag reorder, local persist, unsigned GitHub Release |
| **v0.2** | Flat folders (create / rename / move), remembered folder context |
| **v0.3** | Validated trackpad pinch (and conflict handling), after a bounded feasibility prototype |
| **Later** | Sparkle, signing/notarization, Homebrew, opt-in telemetry/crash reporting, legacy import, badges, polish |

## How we work (gstack-inspired)

PRD → short build plan → coding agent implements → owner tests on real Macs (macOS 26+ target + macOS 15 Launchpad reference) → release notes + GitHub Release → next small slice. Prefer shipping a narrow wedge over waiting for full classic parity.
