# Dotfiles — Omarchy bar widget (mise + Tailscale)

Track dotfiles with [mise](https://mise.jdx.dev/dotfiles.html) and share
them between your machines over [Tailscale](https://tailscale.com) — no
GitHub account required.

The panel has four sections:

- **Setup** — mise / watcher / origin / Tailscale status, enable the
  auto-save watcher, connect a Tailscale git origin.
- **Files** — tracked files, roll back, untrack. Type a path and press
  Enter to track it; each row has three inline action buttons on the right
  — open in the default editor, share via Taildrop, and remove from
  tracking (hover for tooltips) — plus *Share all files* for the whole
  list. *Save all* only appears when auto-save is behind.
- **Activity** — recent checkpoints, sync health, an explicit *Check remote
  now* action, pull, undo, and per-file conflict decisions. With the watcher
  running in `sync` mode, publishing, fetching, and applying conflict-free
  changes happen on their own (see below).
- **Share** — pick a tailnet peer and push one file with Taildrop
  (`tailscale file cp`), or send every tracked file at once. Receiving is
  not in the panel: Omarchy's `omarchy-tailscale-receive.service` already
  collects incoming files into `~/Downloads`.

## How sharing works (Tailscale-only)

Two transports, both staying inside your tailnet:

1. **Full history sync (recommended).** On one machine create a bare repo
   and point every machine at it over Tailscale SSH:
   ```sh
   git init --bare ~/setup.git          # on the "server" machine
   # in the widget: Setup tab → Connect Tailscale origin
   ssh://user@100.x.y.z/~/setup.git
   ```
   From then on the history watcher publishes your checkpoints and
   fetches everyone else's changes and applies conflict-free updates by
   itself (`mise bootstrap dotfiles sync` with mode `sync`) — no button
   needed. *Check remote now* forces a publish + fetch round without making
   merely opening the panel contact the network. *Pull shared changes* is
   available when fetched work is still pending, while conflicts offer
   explicit *Take remote* and *Keep local* decisions.
   Requires `sshd` running on the host machine.

2. **Quick file push.** Share tab → pick an online peer, then hit the
   share button on a row (or *Send all tracked files to peer*). Uses
   `tailscale file cp`; the receiving machine needs nothing from you —
   `omarchy-tailscale-receive.service` collects into `~/Downloads` on its
   own. No git or ssh needed, but no history either — good for
   bootstrapping a new machine.

## Requirements

- `mise` on PATH (any recent version with `mise bootstrap dotfiles`)
- `tailscale` on PATH, logged in (`tailscale status` shows peers)
- Python 3 (for the status helper)

## Install

```sh
omarchy plugin add https://github.com/ofrades/omarchy-dotfiles.git --enable
```

Or hack on it live:

```sh
git clone https://github.com/ofrades/omarchy-dotfiles.git ~/.config/omarchy/plugins/io.github.ofrades.dotfiles
omarchy-shell shell rescanPlugins
```

## Validate

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml
./tests/run
```

## Files

| File | Purpose |
| ---- | ------- |
| `manifest.json` | Plugin contract (`bar-widget`) |
| `BarWidget.qml` | Bar label + popup loader |
| `Panel.qml` | Setup / Files / Activity / Share UI |
| `Service.qml` | mise + tailscale backend over `Process` |
| `Model.js` | Parsing / formatting (node-testable) |
| `dotfiles_status.py` | One-shot JSON status probe |

Plugins run unsandboxed inside `omarchy-shell`. This one only shells out
to `mise`, `tailscale`, `git` (via mise), and `python3` — no network calls
of its own, no sudo. Read the code before enabling.
