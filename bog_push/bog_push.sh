#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bog_push.sh - Automatic homework submission script
# 
# Usage: bog_push.sh <homework_number>
#   homework_number: Number of the homework assignment (e.g., 01, 02, etc.)
#
# This script will:
#   1. Find all a*.out files in the current directory
#   2. Copy them to the appropriate homework directory in the repo
#   3. Pull latest changes from GitHub
#   4. Automatically resolve any conflicts
#   5. Commit and push changes
# ============================================================================

# === Color output for better UX ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# === Check arguments ===
if [ $# -ne 1 ]; then
  error "Invalid number of arguments."
  echo "Usage: bog_push.sh <homework_number>" >&2
  echo "Example: bog_push.sh 01" >&2
  exit 1
fi

HW_NUMBER="$1"

# Validate homework number format (should be a number, optionally zero-padded)
if ! [[ "$HW_NUMBER" =~ ^[0-9]+$ ]]; then
  error "Homework number must be numeric. Got: $HW_NUMBER"
  echo "Example: bog_push.sh 01" >&2
  exit 1
fi

# Ensure two-digit format
HW_NUMBER=$(printf "%02d" "$HW_NUMBER")

# === Find all a*.out files in current directory ===
CURRENT_DIR="$(pwd)"
OUT_FILES=($(find "$CURRENT_DIR" -maxdepth 1 -type f -name 'a*.out' -printf '%f\n' | sort))

if [ ${#OUT_FILES[@]} -eq 0 ]; then
  error "No a*.out files found in current directory: $CURRENT_DIR"
  echo "Fix: Make sure you run this command in a directory containing compiled output files (a01.out, a02.out, etc.)" >&2
  exit 1
fi

echo "Found ${#OUT_FILES[@]} output file(s): ${OUT_FILES[*]}"

# === Determine target directory in repo ===
HW_DIR="${HW_NUMBER}_HW"
TARGET_DIR="$GITHUB_REPO_CLONE_DIR/$HW_DIR/$STUDENT_DISPLAY_NAME"

echo "Target directory: $TARGET_DIR"

# Create target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
  echo "Creating directory: $TARGET_DIR"
  mkdir -p "$TARGET_DIR"
fi

# === Copy files to target directory ===
echo "Copying files..."
for file in "${OUT_FILES[@]}"; do
  cp -v "$CURRENT_DIR/$file" "$TARGET_DIR/"
done

success "Files copied successfully."

# === Change to repository directory ===
cd "$GITHUB_REPO_CLONE_DIR"

# === Ensure SSH key is loaded ===
if [ -n "${GITHUB_SSH_KEY_NAME:-}" ]; then
  if [ -f "$HOME/.ssh/$GITHUB_SSH_KEY_NAME" ]; then
    ssh-add -q "$HOME/.ssh/$GITHUB_SSH_KEY_NAME" 2>/dev/null || true
  fi
fi

# === Configure git to auto-resolve conflicts (ours strategy for simple cases) ===
# Set merge strategy to avoid interactive prompts
git config pull.rebase false
git config merge.ours.driver true

# === Pull latest changes ===
echo "Pulling latest changes from GitHub..."

# Attempt to pull with automatic merge
if git pull origin main --no-edit 2>&1; then
  success "Pull successful."
else
  warning "Pull encountered conflicts. Attempting automatic resolution..."
  
  # Check if there are merge conflicts
  if git status | grep -q "Unmerged paths"; then
    # Get list of conflicted files
    CONFLICTED_FILES=$(git diff --name-only --diff-filter=U)
    
    for conflict_file in $CONFLICTED_FILES; do
      # For our use case, we always want to keep our version
      # since each student works in their own directory
      echo "Resolving conflict in $conflict_file (keeping our version)..."
      git checkout --ours "$conflict_file"
      git add "$conflict_file"
    done
    
    # Complete the merge
    git commit -m "Auto-resolved merge conflicts for $STUDENT_DISPLAY_NAME" --no-edit
    success "Conflicts resolved automatically."
  else
    error "Pull failed but no conflicts detected. Manual intervention may be required."
    exit 1
  fi
fi

# === Stage changes ===
echo "Staging changes..."
git add "$HW_DIR/$STUDENT_DISPLAY_NAME/"

# === Check if there are changes to commit ===
if git diff --cached --quiet; then
  warning "No changes to commit. Files may already be up to date."
  exit 0
fi

# === Commit changes ===
COMMIT_MESSAGE="Add homework $HW_NUMBER for $STUDENT_DISPLAY_NAME"
echo "Committing changes: $COMMIT_MESSAGE"
git commit -m "$COMMIT_MESSAGE"

# === Push changes ===
echo "Pushing to GitHub..."
if git push origin main; then
  success "✓ Homework $HW_NUMBER submitted successfully!"
  echo ""
  echo "Submitted files:"
  for file in "${OUT_FILES[@]}"; do
    echo "  - $file"
  done
else
  error "Push failed."
  echo "This might happen if:"
  echo "  - Your SSH key is not loaded (run: ssh-add ~/.ssh/\$GITHUB_SSH_KEY_NAME)"
  echo "  - You don't have push permissions for the repository"
  echo "  - Network connectivity issues"
  echo ""
  echo "Try running 'git push origin main' manually from: $GITHUB_REPO_CLONE_DIR"
  exit 1
fi
