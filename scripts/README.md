# Curriculum maintenance scripts

## `check-mermaid.mjs`

Validates every ` ```mermaid ` block in the curriculum against mermaid's own parser —
the same gate GitHub uses to decide whether to draw a diagram or show a red
**"syntax error"** box. A clean run means the diagrams render on GitHub.

```bash
cd scripts
npm install                  # one time

npm run check-mermaid        # scan ../curriculum recursively
node check-mermaid.mjs path/to/file.md   # or specific files
```

Exits non-zero on the first failing file, so it drops straight into a pre-commit
hook or CI step. Failures report the file, the line the block starts on, and the
parser error:

```
FAIL curriculum/week-5-ai-workloads/theory/5.4-distributed-training.md:36
     Parse error on line 5: ...r/>8-12 bytes/param (Adam)] Expecting 'SQE', ... got 'PS'
```

### The failure you will hit most often

Unquoted special characters in a node label. Mermaid's flowchart lexer is
shape-driven: `[` opens a label and it scans for the matching `]`, so a bare `(`
reads as the start of a *different* shape (`([` stadium, `[(` cylinder) — hence
`got 'PS'`, the token for "paren start".

```
BROKEN   OPTIM[Optimizer States<br/>8-12 bytes/param (Adam)]
WORKS    OPTIM["Optimizer States<br/>8-12 bytes/param (Adam)"]

BROKEN   W0[GPU 0: W[:, 0:H/4]]
WORKS    W0["GPU 0: W[:, 0:H/4]"]
```

Quoting puts the lexer in string mode, where `(`, `[`, `<`, `:` and `/` are all
just characters. `<br/>` still works inside quotes because line-break expansion
happens at render time, not in the lexer. Quote any label containing `(`, `[`,
`{`, `<`, or `>`.

### What this does *not* catch

Parsing only proves the diagram draws — not that it draws *well*. Two classes of
problem slip through:

- **Orphan nodes.** A node declared with no edges parses fine and renders as a
  box floating in space.
- **Layout collapse.** Subgraphs do not reliably inherit the parent's
  `flowchart TB`; dagre can flatten an inner chain into the parent's rank order
  and squash the diagram into an unreadable horizontal strip. An explicit
  `direction TB` inside the subgraph pins it.

To check those, render to an image and look at it:

```bash
npx -y @mermaid-js/mermaid-cli -i ../curriculum/path/to/file.md -o /tmp/out.md -e png -b white
```
