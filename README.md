# imap-spam-filter

A sidecar spam filter for an existing IMAP mail account. It uses
[bogofilter](https://bogofilter.sourceforge.io/) for statistical spam
classification and [imapfilter](https://github.com/lefcha/imapfilter) to move
detected spam to the Junk folder, with
[goimapnotify](https://gitlab.com/shackra/goimapnotify) driving near-real-time
processing via IMAP IDLE.

## How it works

1. **goimapnotify** watches INBOX via IMAP IDLE. When new mail arrives it
   triggers `classify-mail.sh`.
2. **classify-mail.sh** syncs INBOX locally (via `mbsync`), runs each new
   message through bogofilter, and writes detected spam message IDs to a queue
   file.
3. **imapfilter** reads the queue and moves the spam messages to the Junk folder
   on the server.
4. **bogofilter-learn.sh** runs daily (via a systemd timer), syncs both INBOX
   and Junk, and trains bogofilter on their contents — learning ham from INBOX
   and spam from Junk.

## Prerequisites

`setup.sh` auto-detects the `goimapnotify` binary via `PATH`, so install it
by whichever method suits your distribution before running setup.

### Fedora

```bash
sudo dnf install isync imapfilter bogofilter gettext
```

goimapnotify is not in the Fedora repos — install it via Go:

```bash
sudo dnf install golang
go install gitlab.com/shackra/goimapnotify/cmd/goimapnotify@latest
```

The binary lands in `~/go/bin/`. Make sure that is in your `PATH`.

### Arch Linux

```bash
sudo pacman -S isync imapfilter bogofilter gettext
yay -S goimapnotify
```

### Debian / Ubuntu

```bash
sudo apt install isync imapfilter bogofilter gettext-base
```

goimapnotify is not in the Debian/Ubuntu repos — install it via Go:

```bash
sudo apt install golang-go
go install gitlab.com/shackra/goimapnotify/cmd/goimapnotify@latest
```

The binary lands in `~/go/bin/`. Make sure that is in your `PATH`.

## Setup

### 1. Clone the repository

```bash
git clone <repo-url> ~/imap-spam-filter
cd ~/imap-spam-filter
```

### 2. Create and fill in `config.env`

```bash
cp config.env.example config.env
$EDITOR config.env
```

Set at minimum:

| Variable | Description |
|---|---|
| `IMAP_HOST` | IMAP server hostname |
| `IMAP_PORT` | IMAP port (usually `993`) |
| `IMAP_USER` | Your email address |
| `IMAP_PASS_CMD` | Shell command that prints your password to stdout |
| `INBOX_FOLDER` | Inbox folder name on the server (usually `INBOX`) |
| `JUNK_FOLDER` | Junk/Spam folder name on the server |
| `ACCOUNT_NAME` | Short identifier used for local maildir (no spaces) |
| `DATA_DIR` | Where to store local mail, state, and bogofilter db |

**Password command examples:**

```bash
# Plain text file (readable only by your user):
IMAP_PASS_CMD="cat $HOME/.config/mailpass"

# pass (password-store):
IMAP_PASS_CMD="pass show email/imap"

# GNOME Keyring / secret-tool:
IMAP_PASS_CMD="secret-tool lookup host imap.example.com"
```

### 3. Run setup

```bash
bin/setup.sh
```

This will:
- Create the data directories under `DATA_DIR`
- Generate `config/mbsync/mbsyncrc` and `config/goimapnotify/config.json`
  from their templates
- Install and enable systemd user units to
  `~/.config/systemd/user/`

Re-run `setup.sh` whenever you change `config.env`.

### 4. Bootstrap bogofilter

Bogofilter needs an initial corpus to work well. Do a full sync first, then
train on your existing mail:

```bash
# Sync all mail (both INBOX and Junk)
source config.env && mbsync -c config/mbsync/mbsyncrc "$ACCOUNT_NAME"

# Train bogofilter
bin/bogofilter-learn.sh
```

Aim for at least a few hundred messages in each folder before relying on the
filter.

## Running the services

Allow user services to run without an active login session (run once):

```bash
sudo loginctl enable-linger $USER
```

Enable and start the systemd user services:

```bash
# Real-time spam detection (runs continuously)
systemctl --user enable --now goimapnotify.service

# Daily training run
systemctl --user enable --now bogofilter-learn.timer
```

Check status:

```bash
systemctl --user status goimapnotify.service
systemctl --user status bogofilter-learn.timer
```

Follow logs:

```bash
# IMAP notifier and mbsync
journalctl --user -u goimapnotify -n 50 -f

# imapfilter (spam queue processing)
journalctl --user -t imapfilter -n 50 -f

# bogofilter training runs
journalctl --user -u bogofilter-learn -n 50 -f

# Everything at once (goimapnotify output includes imapfilter via systemd-cat)
journalctl --user -u goimapnotify -u bogofilter-learn -n 50 -f
```

## Manual operation

Run classification manually (e.g. after a long period offline):

```bash
mbsync -c config/mbsync/mbsyncrc "$ACCOUNT_NAME"-inbox
bin/classify-mail.sh
```

Run a training cycle manually:

```bash
bin/bogofilter-learn.sh
```

## Correcting mistakes

Bogofilter learns from corrections automatically via `bogofilter-learn.sh`:

- **False positive** (ham moved to Junk): move the message back to INBOX on
  your mail client. The next training run will relearn it as ham.
- **False negative** (spam left in INBOX): move the message to Junk. The next
  training run will relearn it as spam.

The learn script tracks each message ID in
`$DATA_DIR/state/mailfilter/learned` and handles reclassification when a
message switches folders.
