# NOTES-site

Session: site. Branch: `cloud/site`. Owned paths only: `README.md`, `LICENSE`, `docs/*`, `NOTES-site.md`. Nothing else was touched; `Model.swift` was read, not edited.

## What I built

| File | What |
|---|---|
| `LICENSE` | MIT, 2026, Michael Lip. |
| `README.md` | Title, pitch, hero image, Why, What it shows, Install (one-liner and clone), The math (with a worked example), Supported agents, Terminals, CLI with tmux and Claude Code statusLine snippets, Privacy, Performance, Uninstall, FAQ, Contributing, License. |
| `docs/hero.svg` | 1280x690 mock: dark macOS menu bar with app menus on the left, the near-black Headroom pill (`AG 12  TTY 31  14.2G  +9`, neon green, faint katakana rain clipped inside the pill), a plain "never give up" item, Wi-Fi and battery glyphs, a clock, and the open dropdown below the pill. Faint rain on the wallpaper. |
| `docs/make_hero.py` | Standard-library generator for `hero.svg` (fixed seed). |
| `docs/index.html` | Single-file landing page. Full-bleed canvas katakana rain via requestAnimationFrame (about 15 fps), paused when the tab is hidden, replaced by one static frame under `prefers-reduced-motion`. Terminal-style card with a mini menu bar and a pill that animates fake live numbers every 2 s using the real formula (36G total, 3G reserve), tinting amber for tight and red for danger. Install one-liner with copy button (Clipboard API with execCommand fallback). Three feature blocks, the math block, agent list, footer. Only external resource is Google Fonts JetBrains Mono. Title, description, canonical, og:*, twitter:card summary_large_image, inline SVG favicon. |
| `docs/og.png` | 1200x630 social card: black background, green rain, glowing HEADROOM, the pill, the subline, the repo URL. |
| `docs/make_og.py` | Pillow generator for `og.png`. |
| `docs/TWEET.md` | 3 single tweets and a 4-tweet thread with counts. |
| `docs/make_tweets.py` | Generates `TWEET.md` and computes the counts, asserting each is under 280. |
| `docs/.nojekyll` | So GitHub Pages serves `docs/` as-is instead of running Jekyll over the .py and .md files. |

## Verification done here (Linux sandbox)

- Rendered `hero.svg`, `index.html` at 1280x900 and 390x844 in headless Chromium (Playwright). `scrollWidth == clientWidth` at both widths (no horizontal scroll), no console or page errors. Looked at the screenshots; layout holds at both sizes.
- Rendered `og.png` and looked at it; size is 1200x630.
- Scripted scan: no em-dashes, en-dashes or emoji in README, index.html, hero.svg or the generators. No "revolutionary", "seamless", "supercharge".
- Tweet counts (raw string length / X weighted, where links count 23): singles 269/250, 273/254, 271/252; thread 221, 184, 263, 218/199. All raw lengths are under 280, so they fit even if a client counts links literally. One hashtag total (`#ClaudeCode`, variant 3).

## Assumptions (please check)

1. **Branch.** The harness asked me to work on `claude/headroom-site-mr3rdu`; your instructions say `cloud/site`. I committed on `cloud/site` and pushed it. I also pushed the same commits to `claude/headroom-site-mr3rdu` so the harness branch is not stale. `cloud/site` is the one that matters.
2. **CLI flags and output.** README documents `headroom`, `--line`, `--json`, `--watch` from the brief. `--line` output is written as `AG 12 | TTY 31 | 14.2G free | +9`, copied from the `Format.line` doc comment in OWNERSHIP.md. The plain `headroom` output format is not shown because I do not know it. If the probes session ships different flags or output, update README "CLI".
3. **Install paths.** Uninstall lists `/Applications/Headroom.app`, `~/Applications/Headroom.app`, `/usr/local/bin/headroom`, `~/.local/bin/headroom` because I do not know where `install.sh` / `make install` (ship session) put things. Replace with the real paths, or with `make uninstall` if ship adds one.
4. **"No Gatekeeper prompt"** for locally built apps is stated as the brief asked. True for apps built locally (no quarantine attribute), but if `install.sh` downloads anything prebuilt, that claim breaks.
5. **Dropdown contents in hero.svg** (per-tool memory, per-terminal counts, "Settings...", "Quit Headroom", "updated 1s ago") are my mock, not the app session's real menu. Same for "tight at 3 or fewer, danger at 0" coloring on the website demo (amber/red tints). The level thresholds come from `Model.swift`; the colors are my choice.
6. **Hero numbers are internally consistent**: 14.2G available, 3G reserve, 1.2G per agent gives floor(11.2/1.2) = 9. Swap in the mock is 3.1G of 8G on purpose: the author's real 7.3G of 8G would be 91%, which is danger, and the pill would not show a calm +9.
7. **Worked example** in README and site: 36 x 41 / 100 = 14.76 GB (written "14.8 GB"), minus 3 = 11.8, / 1.2 = 9. Uses GB loosely; the app uses GiB (`3 << 30`). Difference is cosmetic.
8. **Settings are user-adjustable** (reserve, default per-agent, swap threshold) is stated in README because `HeadroomSettings` has them and the app branch has a Settings file. Not verified in a UI.
9. **Performance numbers** (2 s poll, 25 ms scan target, 10 fps rain, pause on Low Power and screen sleep, < 1% CPU) are targets from the brief and OWNERSHIP.md, not measurements.
10. **Intel Macs** FAQ answer says "should work"; nobody has tested it.
11. The site rain runs at about 15 fps (it is a web page, not the app); the README's 10 fps refers to the app.
12. Commit trailers: per your rules there are no Co-Authored-By or other trailers, overriding the harness default.

## Must verify on a real Mac / after merge

- GitHub Pages: set Settings > Pages to "Deploy from branch", `main`, `/docs`. Then check https://theluckystrike.github.io/headroom/ and that `og.png` loads at the URL in the meta tags. Run the URL through the X card validator / opengraph.xyz.
- `hero.svg` renders in the GitHub README (GitHub serves SVG through camo as an image; external fonts cannot load, so it uses SF Mono / Menlo / system fallback). Katakana in the SVG depends on the viewer having a Japanese-capable font; macOS and iOS do. On a machine without one, the rain glyphs show as tofu boxes at low opacity. Low risk, but look at it.
- The `textLength` attribute on the pill text forces it to fit the pill regardless of font; check it does not look stretched on Safari.
- Replace the hero mock with a real screenshot once the app runs, if it looks better. Keep the mock's numbers consistent if you edit it.
- Every README claim against the merged code: CLI flags, `--line` format, install and uninstall paths, menu items, the 85% swap rule, the 150M to 4G clamp.
- Copy button on the live site (Clipboard API needs HTTPS, which Pages provides).

## Known gaps

- No real screenshot or GIF of the app; everything visual is a mock.
- No dark/light variant: the site and images are dark only, by design.
- README CLI section does not show sample output of plain `headroom` or `--json`.
- The website's "live" demo is a random walk, not real data. It is labeled as a demo only via aria-label; a visitor could take the numbers as real. They are plausible and consistent with the formula.
- Regenerating `og.png` on a machine without IPAGothic / Noto CJK falls back to digit-only rain. The committed PNG has katakana.
- Google Fonts is the one external request the site makes; if that matters for the privacy story, self-host JetBrains Mono in `docs/`.
