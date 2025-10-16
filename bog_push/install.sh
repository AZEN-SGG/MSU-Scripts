#!/usr/bin/env bash
set -eEuo pipefail

# Check that git is installed
if ! command -v git > /dev/null 2>&1; then
  echo "Error: git is not installed. Please install git and rerun this script." >&2
  exit 1
fi

# === Variables ===
# Unique timestamp to avoid collisions
TS=$(date +%Y%m%d%H%M%S)
PROGRAM_NAME="install_bogachev_209"
WORKDIR_BACKUP="$HOME/.bashrc.backup.$TS"
ENV_FILE="$HOME/.bogachev_env"
CLEANUP_REQUIRED=false
SSH_KEY_NAME="${PROGRAM_NAME}_${TS}"
CLONE_DIR=""

# === Cleanup on exit or interruption ===
cleanup() {
  if [ "$CLEANUP_REQUIRED" = true ]; then
    echo "Rolling back changes..."
    # Restore bashrc
    if [ -f "$WORKDIR_BACKUP" ]; then
      mv "$WORKDIR_BACKUP" "$HOME/.bashrc"
      echo "Restored original ~/.bashrc"
    fi
    # Remove bogachev environment file
    if [ -f "$ENV_FILE" ]; then
      rm -f "$ENV_FILE"
      echo "Removed ~/.bogachev_env"
    fi
    # Remove generated SSH keys
    if [ -n "$SSH_KEY_NAME" ]; then
      rm -f "$HOME/.ssh/${SSH_KEY_NAME}" "$HOME/.ssh/${SSH_KEY_NAME}.pub"
      echo "Removed SSH key $SSH_KEY_NAME"
    fi
    # Remove clone directory
    if [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ]; then
      rm -rf "$CLONE_DIR"
      echo "Removed clone directory $CLONE_DIR"
    fi
    # Remove bog_push.sh
    SCRIPT_NAME="bog_push.sh"
    DEST_DIR="$HOME/bogachev/bin"
    if [ -f "$DEST_DIR/$SCRIPT_NAME" ]; then
      rm -f "$DEST_DIR/$SCRIPT_NAME"
      echo "Removed installed bog_push script"
    fi
    echo "Cleanup complete. Exiting."
  fi
  exit 1
}
trap cleanup INT TERM EXIT

# === Ensure ~/.bashrc exists ===
if [ ! -f "$HOME/.bashrc" ]; then
  touch "$HOME/.bashrc"
  echo "# Created by bogachev installer" >> "$HOME/.bashrc"
fi

# === Step 1: Backup ~/.bashrc ===
echo "Backing up your ~/.bashrc to $WORKDIR_BACKUP"
cp "$HOME/.bashrc" "$WORKDIR_BACKUP"

CLEANUP_REQUIRED=true

# === Prompt for and validate student display name ===
while true; do
  read -r -p "Enter your student display name (format Lastname_AA): " STUDENT_DISPLAY_NAME
  # Check non-empty
  if [ -z "$STUDENT_DISPLAY_NAME" ]; then
    echo "Error: name cannot be empty." >&2
    continue
  fi
  # Normalize to trim trailing slash/spaces
  STUDENT_DISPLAY_NAME="${STUDENT_DISPLAY_NAME//[[:space:]]/}"
  # Validate pattern: letters + underscore + exactly 2 letters
  if [[ "$STUDENT_DISPLAY_NAME" =~ ^[A-Za-z]+_[A-Za-z]{2}$ ]]; then
    # Upper-case the initials portion
    NAME_PART="${STUDENT_DISPLAY_NAME%%_*}"
    INIT_PART="${STUDENT_DISPLAY_NAME##*_}"
    INIT_PART="${INIT_PART^^}"  # uppercase
    STUDENT_DISPLAY_NAME="$NAME_PART"_"$INIT_PART"
    export STUDENT_DISPLAY_NAME
    break
  else
    echo "Error: invalid format. Expected Lastname_AA (two letters). Try again." >&2
  fi
done

# === Step 2: Generate SSH key pair ===
SSH_PATH="$HOME/.ssh/$SSH_KEY_NAME"
if [ -f "$SSH_PATH" ] || [ -f "$SSH_PATH.pub" ]; then
  echo "Error: $SSH_PATH already exists." >&2
  exit 1
fi
ssh-keygen -t ed25519 -C "$USER@$(hostname)" -f "$SSH_PATH"

# === Step 3: Start ssh-agent and add key ===
eval "$(ssh-agent -s)"
ssh-add "$SSH_PATH"

echo "Copy the following public key and add it to your GitHub account (https://github.com/settings/ssh/new):"
cat "${SSH_PATH}.pub"
echo
read -p "Press Enter once you've added the key on GitHub..." dummy

# === Step 3.1: Add GitHub to known_hosts ===
echo "Adding GitHub to known_hosts..."

# Ensure ~/.ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Add GitHub's SSH keys to known_hosts
# This prevents the "authenticity of host" prompt on first connection
ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
if [ $? -eq 0 ]; then
  echo "GitHub added to known_hosts successfully."
else
  echo "Warning: Could not add GitHub to known_hosts automatically." >&2
fi

# === Step 3.2: Verify SSH auth to GitHub ===
echo "Verifying SSH access to GitHub..."

SSH_TEST_OUTPUT=$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)
if echo "$SSH_TEST_OUTPUT" | grep -q "successfully authenticated"; then
  echo "SSH connection to GitHub: OK"
else
  echo "Error: Unable to authenticate with GitHub over SSH. Please check that your key is added to your account." >&2
  echo "Debug output:"
  echo "$SSH_TEST_OUTPUT" >&2
  exit 1
fi

# === Step 4: Configure environment variables ===
# Directory to clone into
read -r -p "Enter directory path where to clone the repository (absolute path): " CLONE_DIR

# === Step 4.1: Prepare clone directory ===
# Fail if directory already exists
if [ -e "$CLONE_DIR" ]; then
  echo "Error: directory $CLONE_DIR already exists; please choose an empty or non-existent path." >&2
  exit 1
fi

# Create target directory
mkdir -p "$CLONE_DIR"

# === Step 4.2: Clone the repository via SSH ===
REPO_SSH_URL="git@github.com:Bogachev-s-group-of-2024/3rd_Semester.git"

# Clone and then verify
echo "Cloning $REPO_SSH_URL into $CLONE_DIR ..."
git clone "$REPO_SSH_URL" "$CLONE_DIR"
if [ ! -d "$CLONE_DIR/.git" ]; then
  echo "Error: Clone failed or repository not found in $CLONE_DIR" >&2
  exit 1
else
  echo "Repository successfully cloned into $CLONE_DIR"
fi

# === Write bogachev environment file ===
cat > "$ENV_FILE" <<EOF
# GitHub SSH and Repo settings
export GITHUB_SSH_KEY_NAME="$SSH_KEY_NAME"
export GITHUB_REPO_CLONE_DIR="$CLONE_DIR"
export STUDENT_DISPLAY_NAME="$STUDENT_DISPLAY_NAME"

# Auto-start ssh-agent and load key if not already running
if ! pgrep -u "\$USER" ssh-agent > /dev/null; then
  eval "\$(ssh-agent -s)"
fi
if [ -f "\$HOME/.ssh/\${GITHUB_SSH_KEY_NAME}" ]; then
  ssh-add -q "\$HOME/.ssh/\${GITHUB_SSH_KEY_NAME}" || true
fi
EOF

# === Make bogachev_env load on every new shell ===
# Append to ~/.bashrc if not already present
if ! grep -q "bogachev_env" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# Source bogachev environment if it exists (interactive shells only)
if [ -f "$HOME/.bogachev_env" ]; then
  case "$-" in
    *i*) source "$HOME/.bogachev_env" ;;
  esac
fi
EOF
fi

# === Step 5: Install bog_push helper ===
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="bog_push.sh"
SRC_PATH="$INSTALL_DIR/$SCRIPT_NAME"
DEST_DIR="$HOME/bogachev/bin"
DEST_PATH="$DEST_DIR/$SCRIPT_NAME"

# Create ~/bogachev/bin directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Check that the source script actually exists
if [ ! -f "$SRC_PATH" ]; then
  echo "Error: bog_push.sh not found at $SRC_PATH" >&2
  exit 1
fi

# Copy the bog_push script into ~/bogachev/bin and make it executable
cp "$INSTALL_DIR/$SCRIPT_NAME" "$DEST_PATH"
chmod +x "$DEST_PATH"
echo "Copied bog_push script to $DEST_PATH"

# Add ~/bogachev/bin to PATH in ~/.bashrc if it's not already there
if ! grep -qx 'export PATH="$HOME/bogachev/bin:$PATH"' "$ENV_FILE"; then
  echo '' >> "$ENV_FILE"
  echo '# Add user bin for bog_push' >> "$ENV_FILE"
  echo 'export PATH="$HOME/bogachev/bin:$PATH"' >> "$ENV_FILE"
  echo "Added ~/bogachev/bin to PATH in ~/.bashrc"
fi

# === Apply new environment to this shell immediately ===
echo "Reloading shell environment..."
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  echo "Environment loaded: STUDENT_DISPLAY_NAME=$STUDENT_DISPLAY_NAME, PATH updated, ssh-agent running."
fi

# === Final step: Confirm ===
echo "Setup complete!"
echo "SSH key: $SSH_PATH"
echo "Repo cloned to: $GITHUB_REPO_CLONE_DIR"

# Disable cleanup on normal exit
CLEANUP_REQUIRED=false

