# Installing Board Skills for Codex

Enable Board Skills in Codex via native skill discovery. Clone and symlink.

## Prerequisites

- Git
- sshpass (`brew install hudochenkov/sshpass/sshpass` on macOS)

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/zhaoxiaowei/rk3588-skills.git ~/.codex/board-skills
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/board-skills/skills ~/.agents/skills/board-skills
   ```

3. **Restart Codex** (quit and relaunch) to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/board-skills
```

## Updating

```bash
cd ~/.codex/board-skills && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/board-skills
```
