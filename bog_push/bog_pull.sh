#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bog_pull.sh - Aggressive repository update script
# 
# This script updates the local repository with all latest changes from GitHub.
# It ALWAYS accepts remote changes, overriding any local modifications.
#
# Usage: bog_pull.sh
#
# What it does:
#   1. Fetches latest changes from GitHub
#   2. Resets local repository to match remote exactly
#   3. Shows what was updated
# ============================================================================

# === Color output for better UX ===
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
  echo -e "${YELLOW}Warning: $1${NC}"
}

info() {
  echo -e "${BLUE}$1${NC}"
}

# === Check required environment variables ===
if [ -z "${STUDENT_DISPLAY_NAME:-}" ]; then
  error "STUDENT_DISPLAY_NAME is not set."
  echo "Fix: Run the installation script first or manually set the variable in ~/.bogachev_env" >&2
  exit 1
fi

if [ -z "${GITHUB_REPO_CLONE_DIR:-}" ]; then
  error "GITHUB_REPO_CLONE_DIR is not set."
  echo "Fix: Run the installation script first or manually set the variable in ~/.bogachev_env" >&2
  exit 1
fi

if [ ! -d "$GITHUB_REPO_CLONE_DIR" ]; then
  error "Repository directory does not exist: $GITHUB_REPO_CLONE_DIR"
  echo "Fix: Check that the repository was cloned successfully during installation." >&2
  exit 1
fi

if [ ! -d "$GITHUB_REPO_CLONE_DIR/.git" ]; then
  error "Directory $GITHUB_REPO_CLONE_DIR is not a git repository."
  echo "Fix: Re-run the installation script to clone the repository properly." >&2
  exit 1
fi

# === Change to repository directory ===
cd "$GITHUB_REPO_CLONE_DIR"

# === Ensure SSH key is loaded ===
if [ -n "${GITHUB_SSH_KEY_NAME:-}" ]; then
  if [ -f "$HOME/.ssh/$GITHUB_SSH_KEY_NAME" ]; then
    ssh-add -q "$HOME/.ssh/$GITHUB_SSH_KEY_NAME" 2>/dev/null || true
  fi
fi

echo ""
info "=========================================="
info "  Repository Update (bog_pull)"
info "=========================================="
echo ""
echo "Repository: $GITHUB_REPO_CLONE_DIR"
echo ""

# === Get current status before update ===
CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# === Step 1: Fetch latest changes ===
echo "Fetching latest changes from GitHub..."
if ! git fetch origin main 2>&1; then
  error "Failed to fetch from GitHub."
  echo "This might happen if:"
  echo "  - Your SSH key is not loaded (run: ssh-add ~/.ssh/\$GITHUB_SSH_KEY_NAME)"
  echo "  - Network connectivity issues"
  echo "  - Repository access problems"
  exit 1
fi
success "✓ Fetch successful"

# === Step 2: Check if update is needed ===
REMOTE_COMMIT=$(git rev-parse origin/main 2>/dev/null)

if [ "$CURRENT_COMMIT" = "$REMOTE_COMMIT" ]; then
  success "✓ Repository is already up to date!"
  echo ""
  echo "Current commit: ${CURRENT_COMMIT:0:8}"
  exit 0
fi

# === Step 3: Save info about local changes (if any) ===
if ! git diff-index --quiet HEAD 2>/dev/null; then
  warning "You have local uncommitted changes."
  echo "These will be DISCARDED to ensure clean update."
  echo ""
fi

# === Step 4: Aggressive reset to remote state ===
echo "Resetting repository to match remote exactly..."

# Discard all local changes (tracked files)
git reset --hard origin/main

# Remove untracked files and directories
git clean -fd

success "✓ Repository reset to remote state"

# === Step 5: Show what was updated ===
echo ""
NEW_COMMIT=$(git rev-parse HEAD)

if [ "$CURRENT_COMMIT" != "unknown" ] && [ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Changes summary:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Show files that changed
  echo "Modified files:"
  git diff --name-status ${CURRENT_COMMIT}..${NEW_COMMIT} | head -20
  
  # Count total changes
  TOTAL_CHANGES=$(git diff --name-only ${CURRENT_COMMIT}..${NEW_COMMIT} | wc -l)
  echo ""
  if [ "$TOTAL_CHANGES" -gt 20 ]; then
    echo "... and $(($TOTAL_CHANGES - 20)) more files"
  fi
  
  echo ""
  echo "Commit range: ${CURRENT_COMMIT:0:8} → ${NEW_COMMIT:0:8}"
fi

echo ""
success "=========================================="
success "  ✓ Update Complete!"
success "=========================================="
echo ""
echo "Your repository is now synchronized with GitHub."
echo "All remote changes have been applied."
echo ""

