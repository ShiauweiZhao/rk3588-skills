# Installing RK3588 Skills for Codex

Enable RK3588 skills in Codex via native skill discovery. Clone and symlink.

## Prerequisites

- Git
- sshpass (`brew install hudochenkov/sshpass/sshpass` on macOS)

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/zhaoxiaowei/rk3588-skills.git ~/.codex/rk3588-skills
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/rk3588-skills/skills ~/.agents/skills/rk3588-skills
   ```

3. **Restart Codex** (quit and relaunch) to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/rk3588-skills
```

## Updating

```bash
cd ~/.codex/rk3588-skills && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/rk3588-skills
```
