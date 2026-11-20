---
name: animation-debug
description: Debug an Argos UI change that adds or changes an animation or transition, by capturing it frame by frame with Playwright and reviewing the frames. Use while developing, after changing Angular animations, CSS transitions, or anything that moves or fades; not for PR screenshots (open-pr).
user-invocable: true
---

A screenshot shows one instant, and Playwright can't take them fast enough (30-100 ms each) to catch a 100 ms animation. So after the trigger, the script pauses the page's animations and steps their time, which gives the same frames on every run, and before/after comparisons mean something. When nothing is animating, or you ask for it, it takes screenshots in real time instead, so any trigger gives you a series. The frames are for debugging; they're never committed.

1. **Run the app** with `run-local <branch>` (the ticket's worktree, from `new-worktree`). Its client URL is `BASE_URL`.
2. **Find the trigger:** the page URL, what to click or hover (a Playwright selector, such as `text=BMS` or `role=button[name='Pause']`), and a short kebab-case name for the animation. A route change is a click on the link that causes it.
3. **Capture:**

   ```bash
   bash scripts/capture.sh <branch> "$BASE_URL/<page>" <animation-name> <click|hover> '<selector>' [<window-ms> [<step-ms> [clock|live]]]
   ```

   Defaults are a frame every 10 ms over 100 ms (11 frames); both are settings. Set the window to the animation's duration (an Angular `animate('400ms')` needs 400) and widen the step for a long one. It saves `pictures/<branch>/<animation-name>/NN-<ms>ms.png`, replacing earlier frames of that name, and exits 1 with a `FAIL` line only if a click or selector fails. The first line says how it captured: `of N animation(s)` means it froze them; `in real time` means it did not.
4. **Review the frames in order**, first to last, and judge each against what the diff intends:
   - Jank: a frame that jumps ahead of or behind its neighbours.
   - Easing: spacing between frames matches the declared easing (even for `linear`, bunched at the ends for `ease-in-out`).
   - Flicker: an element that vanishes or reappears between frames, or a flash of the end state in the first frame.
   - Start and end: the first frame is the start state and the last is the declared end state, with no leftover offset or opacity.
5. **Report** the folder and one line per problem, naming the frame.

Each frame is the whole page, so the navbar clock and live charts differ between runs even when an animation is frozen: judge the animated area, not the whole picture. To compare a change, capture the same trigger from `develop`'s client and from the branch's, under names like `nub-before` and `nub-after`.

A trigger often sits behind other clicks (a tree to open, a menu). Give those as `SETUP='<selector>;;<selector>'` in the environment and they are clicked first, in order, from a fresh page load; only the last click, the trigger, starts the capture.

For what pausing can't freeze, such as a chart drawing in as data arrives, pass `live` as the last argument (`… 3000 250 live`) to take real-time screenshots. Frames are named by when each was taken, they differ between runs, and each takes 30 ms or more, so a 10 ms step can't be met: the output reports the real spacing. Use `live` on a page that always has other animations running (the graph page has about 26 from page load), because the default would freeze those instead of what you clicked.

For timer or `requestAnimationFrame` animations, which pausing can't reach, pass `clock` as the last argument (`… 100 10 clock`) to step the page's fake clock instead. The fake `requestAnimationFrame` ticks every 16 ms, so frames land on those ticks rather than exactly on the step.

The browser session stays open after a capture; `playwright-cli -s=<branch> close` ends it.
