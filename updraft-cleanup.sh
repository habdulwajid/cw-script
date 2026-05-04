#!/bin/bash
# UpdraftPlus Cleanup Script - Multi-App Server
# Removes ONLY the contents of /wp-content/updraft/ — folder itself is kept

echo "================================================"
echo "   UpdraftPlus Cleanup Script - Multi-App"
echo "================================================"
echo ""

# -----------------------------------------------
# COLLECT APP NAMES FROM NGINX
# -----------------------------------------------
APPS=()
for config in /etc/nginx/sites-available/*; do
  APP=$(basename "$config")
  APPS+=("$APP")
done

if [ ${#APPS[@]} -eq 0 ]; then
  echo "[ERROR] No apps found in /etc/nginx/sites-available/"
  exit 1
fi

echo "Found ${#APPS[@]} app(s): ${APPS[*]}"
echo ""

REMOVED_FILES=()
SKIPPED_APPS=()

# -----------------------------------------------
# LOOP THROUGH EACH APP
# -----------------------------------------------
for APP in "${APPS[@]}"; do

  BASE_PATH="/home/master/applications/$APP/public_html"
  UPDRAFT_PATH="/home/master/applications/$APP/public_html/wp-content/updraft"

  echo "------------------------------------------------"
  echo "App:          $APP"
  echo "Base Path:    $BASE_PATH"
  echo "Updraft Path: $UPDRAFT_PATH"

  # Guard 1: APP must not be empty or contain path traversal characters
  if [[ -z "$APP" || "$APP" == *"/"* || "$APP" == *".."* ]]; then
    echo "[ABORT]    App name is invalid or contains unsafe characters: '$APP'"
    SKIPPED_APPS+=("$APP (invalid app name)")
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 2: Validate the base path exists
  if [ ! -d "$BASE_PATH" ]; then
    echo "[SKIP]     Base path does not exist."
    SKIPPED_APPS+=("$APP (base path not found)")
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 3: Validate this is a WordPress install
  if [ ! -f "$BASE_PATH/wp-config.php" ]; then
    echo "[SKIP]     No wp-config.php found. Not a WordPress install."
    SKIPPED_APPS+=("$APP (not a WordPress install)")
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 4: Validate updraft directory exists
  if [ ! -d "$UPDRAFT_PATH" ]; then
    echo "[INFO]     No updraft folder found. Nothing to remove."
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 5: Strictly confirm UPDRAFT_PATH is exactly what we expect
  # Prevents any symlink, variable, or resolution issues from targeting wrong path
  EXPECTED_PATH="/home/master/applications/$APP/public_html/wp-content/updraft"
  if [ "$UPDRAFT_PATH" != "$EXPECTED_PATH" ]; then
    echo "[ABORT]    Path mismatch detected. Refusing to delete."
    echo "           Expected: $EXPECTED_PATH"
    echo "           Got:      $UPDRAFT_PATH"
    SKIPPED_APPS+=("$APP (path mismatch — skipped for safety)")
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 6: Ensure the path is not a symlink
  if [ -L "$UPDRAFT_PATH" ]; then
    echo "[ABORT]    Updraft path is a symlink. Refusing to delete."
    SKIPPED_APPS+=("$APP (symlink detected — skipped for safety)")
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # Guard 7: Ensure updraft folder is not empty
  FILE_COUNT=$(find "$UPDRAFT_PATH" -mindepth 1 -type f | wc -l)
  if [ "$FILE_COUNT" -eq 0 ]; then
    echo "[INFO]     Updraft folder is already empty. Nothing to remove."
    echo "[NEXT]     Moving to next app..."
    echo ""
    continue
  fi

  # -----------------------------------------------
  # AUDIT SUMMARY BEFORE DELETION
  # -----------------------------------------------
  DIR_SIZE=$(du -sh "$UPDRAFT_PATH" | cut -f1)
  echo "[AUDIT]    Files to be removed: $FILE_COUNT"
  echo "[AUDIT]    Total size:          $DIR_SIZE"

  # -----------------------------------------------
  # REMOVE ONLY CONTENTS — KEEP DIRECTORY ITSELF
  # -mindepth 1 ensures the updraft folder itself is never deleted
  # -----------------------------------------------
  echo "[REMOVING] Clearing contents of $UPDRAFT_PATH ..."

  find "$UPDRAFT_PATH" -mindepth 1 -delete

  # Verify directory is now empty
  REMAINING=$(find "$UPDRAFT_PATH" -mindepth 1 | wc -l)
  if [ "$REMAINING" -eq 0 ]; then
    echo "[DONE]     Removed $FILE_COUNT files ($DIR_SIZE) from $UPDRAFT_PATH"
    echo "[KEPT]     Directory retained: $UPDRAFT_PATH"
    REMOVED_FILES+=("[$APP] $UPDRAFT_PATH — $FILE_COUNT files, $DIR_SIZE cleared")
  else
    echo "[WARNING]  $REMAINING file(s) could not be removed in $UPDRAFT_PATH"
    SKIPPED_APPS+=("$APP (partial removal — $REMAINING files remaining)")
  fi

  echo "[NEXT]     Moving to next app..."
  echo ""

done

# -----------------------------------------------
# SUMMARY REPORT
# -----------------------------------------------
echo "================================================"
echo "   CLEANUP SUMMARY"
echo "================================================"
echo ""

if [ ${#REMOVED_FILES[@]} -eq 0 ]; then
  echo "No updraft contents were found or removed."
else
  echo "Successfully cleared:"
  echo ""
  for entry in "${REMOVED_FILES[@]}"; do
    echo "  - $entry"
  done
fi

echo ""
if [ ${#SKIPPED_APPS[@]} -gt 0 ]; then
  echo "Skipped / warnings:"
  for skipped in "${SKIPPED_APPS[@]}"; do
    echo "  - $skipped"
  done
fi

echo ""
echo "================================================"
echo "Done."
echo "================================================"
