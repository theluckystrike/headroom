# Launch tweets

Character counts are computed by script. "raw" is the plain string length; "X" is how X counts it (every link counts as 23). Every count is under 280.

## Single tweets

### Variant 1 (raw 269, X 250)

```
I run a dozen Claude Code, Codex and Hermes agents in 100+ terminals. My Mac sometimes crashes when too many run.

So I built Headroom, a menu bar meter that shows how many more agents I can still start, based on memory left.

https://github.com/theluckystrike/headroom
```

### Variant 2 (raw 273, X 254)

```
Every time I opened one more agent I was guessing. Sometimes the guess was wrong and the whole Mac went down.

Headroom sits in the menu bar and answers it: AG 12  TTY 31  14.2G  +9. +9 means 9 more agents fit in the memory left.

https://github.com/theluckystrike/headroom
```

### Variant 3 (raw 271, X 252)

```
I made Headroom, a tiny Matrix-style macOS menu bar app for running fleets of AI coding agents.

It counts agents, terminals and free memory, then shows how many more agents fit before my Mac swaps hard and crashes. #ClaudeCode

https://github.com/theluckystrike/headroom
```

## Thread (4 tweets)

### 1/4 (raw 221, X 221)

```
My Mac has crashed more than once because I had too many AI coding agents running: Claude Code, Codex, Hermes, across 100+ terminals.

So I built a menu bar app that tells me how many more I can start before that happens.
```

### 2/4 (raw 184, X 184)

```
It shows four numbers in neon green on a black pill:

AG 12  TTY 31  14.2G  +9

Agents running, terminal sessions, memory available, and the one that matters: how many more agents fit.
```

### 3/4 (raw 263, X 263)

```
The math is simple and in the README:

available = total x memorystatus_level / 100
per agent = median footprint of running agent trees, MCP servers included
headroom = (available - 3G reserve) / per agent

No network, no telemetry. Native Swift, no dependencies.
```

### 4/4 (raw 218, X 199)

```
It is called Headroom. Free and MIT licensed, macOS 13+. Install builds it from source, so no Gatekeeper prompt.

There is also a CLI for tmux and the Claude Code statusLine.

https://github.com/theluckystrike/headroom
```

Attach docs/og.png (or a screenshot of the real menu bar once the app runs) to the first tweet.
