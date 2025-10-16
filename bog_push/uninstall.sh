#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# uninstall.sh - Uninstall script for Bogachev homework submission system
#
# This script reverses all changes made by install.sh:
#   - Removes SSH keys
#   - Removes environment file
#   - Removes bog_push script and ~/bogachev directory
#   - Removes bashrc modifications
#   - Optionally removes the cloned repository
# ============================================================================

# === Color output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() {
  echo -e "${RED}Error: $1${NC}" >&2
}

success() {
  echo -e "${GREEN}$1${NC}"
}

warning() {
  echo -e "${YELLOW}$1${NC}"
}

info() {
  echo -e "${BLUE}$1${NC}"
}

# === Load environment variables if they exist ===
ENV_FILE="$HOME/.bogachev_env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  info "Loaded environment from $ENV_FILE"
else
  warning "Environment file not found at $ENV_FILE"
  echo "Continuing with uninstall anyway..."
fi

echo ""
info "=========================================="
info "  Bogachev System Uninstaller"
info "=========================================="
echo ""

# === Confirm uninstallation ===
echo "This will remove:"
echo "  - SSH key: ${GITHUB_SSH_KEY_NAME:-<not set>}"
echo "  - Environment file: $ENV_FILE"
echo "  - bog_push script and ~/bogachev directory"
echo "  - Modifications to ~/.bashrc"
echo ""

read -p "Do you want to continue? [y/N]: " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Uninstall cancelled."
  exit 0
fi

echo ""

# === Step 1: Remove SSH keys ===
if [ -n "${GITHUB_SSH_KEY_NAME:-}" ]; then
  SSH_KEY_PATH="$HOME/.ssh/$GITHUB_SSH_KEY_NAME"
  SSH_PUB_PATH="$HOME/.ssh/${GITHUB_SSH_KEY_NAME}.pub"
  
  if [ -f "$SSH_KEY_PATH" ] || [ -f "$SSH_PUB_PATH" ]; then
    echo "Removing SSH keys..."
    
    # Remove from ssh-agent if loaded
    ssh-add -d "$SSH_KEY_PATH" 2>/dev/null || true
    
    # Remove key files
    rm -f "$SSH_KEY_PATH" "$SSH_PUB_PATH"
    success "✓ SSH keys removed"
  else
    info "SSH keys not found (may have been removed already)"
  fi
else
  info "SSH key name not set, skipping key removal"
fi

# === Step 2: Remove bog_push script and ~/bogachev directory ===
BOGACHEV_DIR="$HOME/bogachev"
if [ -d "$BOGACHEV_DIR" ]; then
  echo "Removing ~/bogachev directory..."
  rm -rf "$BOGACHEV_DIR"
  success "✓ ~/bogachev directory removed"
else
  info "~/bogachev directory not found"
fi

# === Step 3: Remove environment file ===
if [ -f "$ENV_FILE" ]; then
  echo "Removing environment file..."
  rm -f "$ENV_FILE"
  success "✓ Environment file removed"
else
  info "Environment file not found"
fi

# === Step 4: Remove bashrc modifications ===
if [ -f "$HOME/.bashrc" ]; then
  echo "Removing modifications from ~/.bashrc..."
  
  # Create a temporary file
  TEMP_FILE=$(mktemp)
  
  # Remove the bogachev_env source block
  # We'll use sed to remove lines between our markers and the block itself
  awk '
    /^# Source bogachev environment if it exists/ {
      # Skip this line and the next few lines until we find the fi
      skip=1
      next
    }
    skip && /^fi$/ {
      # Found the end of the block, skip this line too and stop skipping
      skip=0
      next
    }
    skip && /^  esac$/ {
      # Part of our block, skip
      next
    }
    skip && /case.*in$/ {
      # Part of our block, skip
      next
    }
    skip && /if \[ -f.*bogachev_env.*\]; then$/ {
      # Part of our block, skip
      next
    }
    skip && /\*i\).*source.*bogachev_env/ {
      # Part of our block, skip
      next
    }
    !skip {
      # Not skipping, print the line
      print
    }
  ' "$HOME/.bashrc" > "$TEMP_FILE"
  
  # Replace the original file
  mv "$TEMP_FILE" "$HOME/.bashrc"
  
  success "✓ ~/.bashrc cleaned"
else
  warning "~/.bashrc not found"
fi

# === Step 5: Remove .bashrc backups (optional) ===
echo ""
BACKUP_COUNT=$(find "$HOME" -maxdepth 1 -name ".bashrc.backup.*" 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 0 ]; then
  read -p "Found $BACKUP_COUNT .bashrc backup file(s). Remove them? [y/N]: " -r REMOVE_BACKUPS
  if [[ "$REMOVE_BACKUPS" =~ ^[Yy]$ ]]; then
    find "$HOME" -maxdepth 1 -name ".bashrc.backup.*" -delete
    success "✓ Backup files removed"
  else
    info "Backup files kept"
  fi
fi

# === Step 6: Ask about repository ===
echo ""
if [ -n "${GITHUB_REPO_CLONE_DIR:-}" ] && [ -d "$GITHUB_REPO_CLONE_DIR" ]; then
  warning "Repository directory: $GITHUB_REPO_CLONE_DIR"
  read -p "Do you want to remove the cloned repository? [y/N]: " -r REMOVE_REPO
  if [[ "$REMOVE_REPO" =~ ^[Yy]$ ]]; then
    rm -rf "$GITHUB_REPO_CLONE_DIR"
    success "✓ Repository removed"
  else
    info "Repository kept at: $GITHUB_REPO_CLONE_DIR"
  fi
else
  info "Repository directory not found or not set"
fi

# === Final message ===
echo ""
success "=========================================="
success "  Uninstall complete!"
success "=========================================="
echo ""
echo "To complete the uninstallation:"
echo "  1. Remove the SSH key from your GitHub account:"
echo "     https://github.com/settings/keys"
echo "  2. Restart your shell or run: source ~/.bashrc"
echo ""
info "If you want to reinstall, run install.sh again."

