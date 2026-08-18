---
name: readme-demo
description: Create animated terminal demos for READMEs with VHS tape files — scripted, reproducible GIFs committed to the repo and embedded by relative path. Use when asked to add a demo video/GIF to a README or record a CLI feature.
argument-hint: "what to demo, e.g. 'the local-llm-router drafting a commit message'"
---

# README Demo (VHS)

Terminal demos as code: a `.tape` script checked into the repo, rendered to
a GIF with `vhs`, embedded in the README by relative path. Anyone can
regenerate the demo with one command; the GIF autoplays inline on GitHub.

## Workflow

1. **Script it.** Write `docs/demos/<name>.tape`. If the demo needs setup or
   a long command, wrap it in a sibling `docs/demos/<name>.sh` so the tape
   stays a clean sequence of what the viewer should see.
2. **Render.** From the repo root: `nix run nixpkgs#vhs -- docs/demos/<name>.tape`
   (vhs bundles ttyd + ffmpeg; works headless).
3. **Check the budget.** GIF under ~5 MB (10 MB is GitHub's render limit),
   640–900 px wide, 10–14 fps, 3–10 s per clip. Several short clips beat one
   long one. Shrink with lower `Framerate`, smaller `Width/Height`, shorter
   `Sleep`s, or `Set PlaybackSpeed 1.5`.
4. **Embed** with a relative link and real alt text, plus a one-line text
   description nearby (GIFs have no pause control or captions):

   ```markdown
   ![local-llm-router drafting a commit message from a diff](docs/demos/local-llm-router.gif)
   ```

5. **Commit** both the `.tape` (and helper script) and the `.gif` — the tape
   is the source of truth; note the regen command near the embed.

## Tape template

```tape
Output docs/demos/<name>.gif
Set FontSize 15
Set Width 900
Set Height 420
Set Padding 12
Set TypingSpeed 40ms
Set Framerate 12

Type "the-command --to demo"
Enter
Wait+Screen@60s /expected-output-regex/
Sleep 3s
```

Useful commands: `Type@500ms` (per-key delay), `Hide`/`Show` (run setup
invisibly), `Wait+Screen@<timeout> /re/` (sync on output — always prefer
over guessing `Sleep`s for slow commands), `Screenshot out.png`,
`Set Theme "Catppuccin Mocha"`, `Require <binary>` (fail fast).

## Embedding rules (GitHub)

- Committed GIF + relative path: autoplays, loops, works everywhere. This is
  the default.
- Uploaded MP4 (drag into the README **web editor**; renders a click-to-play
  player): only for long demos where scrubbing matters. Limits: 10 MB free
  plan / 100 MB paid. Cannot be done from the CLI; repo-committed `.mp4`
  files and `<video src>`/`<iframe>` tags do NOT render.
- Dark/light variants: `<picture>` + `prefers-color-scheme` sources is the
  supported mechanism (render the tape twice with different `Set Theme`).

## GUI demos (Sway/Wayland)

Terminal tools can't capture GUI apps. Record with
`wf-recorder -g "$(slurp)" -f demo.mp4`, then convert:
`ffmpeg -i demo.mp4 -vf "fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" demo.gif`
(or `gifski` for higher quality). Same size budget applies.

## Checklist

- [ ] Tape + helper script committed next to the GIF
- [ ] GIF < 5 MB, autoplay-safe (no rapid flashing)
- [ ] Alt text describes what happens, not "demo gif"
- [ ] Regen command documented near the embed
