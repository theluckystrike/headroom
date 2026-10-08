"""Generate docs/TWEET.md with computed character counts. Run: python3 docs/make_tweets.py"""
import os
import re
URL="https://github.com/theluckystrike/headroom"
singles=[
f"""I run a dozen Claude Code, Codex and Hermes agents in 100+ terminals. My Mac sometimes crashes when too many run.

So I built Headroom, a menu bar meter that shows how many more agents I can still start, based on memory left.

{URL}""",
f"""Every time I opened one more agent I was guessing. Sometimes the guess was wrong and the whole Mac went down.

Headroom sits in the menu bar and answers it: AG 12  TTY 31  14.2G  +9. +9 means 9 more agents fit in the memory left.

{URL}""",
f"""I made Headroom, a tiny Matrix-style macOS menu bar app for running fleets of AI coding agents.

It counts agents, terminals and free memory, then shows how many more agents fit before my Mac swaps hard and crashes. #ClaudeCode

{URL}""",
]
thread=[
"""My Mac has crashed more than once because I had too many AI coding agents running: Claude Code, Codex, Hermes, across 100+ terminals.

So I built a menu bar app that tells me how many more I can start before that happens.""",
"""It shows four numbers in neon green on a black pill:

AG 12  TTY 31  14.2G  +9

Agents running, terminal sessions, memory available, and the one that matters: how many more agents fit.""",
"""The math is simple and in the README:

available = total x memorystatus_level / 100
per agent = median footprint of running agent trees, MCP servers included
headroom = (available - 3G reserve) / per agent

No network, no telemetry. Native Swift, no dependencies.""",
f"""It is called Headroom. Free and MIT licensed, macOS 13+. Install builds it from source, so no Gatekeeper prompt.

There is also a CLI for tmux and the Claude Code statusLine.

{URL}""",
]
def wc(t):  # X counts any URL as 23 chars
    return len(re.sub(r'https?://\S+','x'*23,t))
out=["# Launch tweets","","Character counts are computed by script. \"raw\" is the plain string length; \"X\" is how X counts it (every link counts as 23). Every count is under 280.",""]
out.append("## Single tweets\n")
for i,t in enumerate(singles,1):
    print("single",i,len(t),wc(t),flush=True); assert len(t)<280
    out+= [f"### Variant {i} (raw {len(t)}, X {wc(t)})","","```",t,"```",""]
out.append("## Thread (4 tweets)\n")
for i,t in enumerate(thread,1):
    print("thread",i,len(t),wc(t),flush=True); assert len(t)<280
    out+= [f"### {i}/4 (raw {len(t)}, X {wc(t)})","","```",t,"```",""]
out+=["Attach docs/og.png (or a screenshot of the real menu bar once the app runs) to the first tweet."]
open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"TWEET.md"),"w").write("\n".join(out)+"\n")
