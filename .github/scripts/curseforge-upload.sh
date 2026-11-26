#!/usr/bin/env bash
# Uploads a release zip to CurseForge.
# Usage: curseforge-upload.sh <zip> <version>
# Env:   CF_API_KEY       CurseForge API token (secret)
#        CF_PROJECT_ID    numeric CurseForge project ID
#        CF_GAME_VERSION  game version name to tag the file with (default 1.60.1, WoW Forever)
#        CHANGELOG        markdown changelog for the file (optional)
set -euo pipefail

zip="$1"
version="$2"
game_version="${CF_GAME_VERSION:-1.60.1}"
api="https://wow.curseforge.com/api"

# Look up CurseForge's internal ID for the game version.
versions=$(curl -sS --fail-with-body -H "X-Api-Token: $CF_API_KEY" "$api/game/versions")
ids=$(jq -c --arg name "$game_version" '[.[] | select(.name == $name) | .id]' <<< "$versions")
count=$(jq 'length' <<< "$ids")
if [ "$count" -eq 0 ]; then
  echo "::error::CurseForge has no game version named '$game_version'. Close matches:"
  jq -r --arg p "${game_version%%.*}." '.[] | select(.name | startswith($p)) | "  \(.name) (id \(.id), type \(.gameVersionTypeID))"' <<< "$versions" | tail -20
  echo "Set the repository variable CF_GAME_VERSION to the right name."
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "::warning::'$game_version' matches $count CurseForge game versions, tagging all of them: $ids"
fi

metadata=$(jq -n \
  --arg name "AlwaysOnDisplay v$version" \
  --arg changelog "${CHANGELOG:-Release v$version}" \
  --argjson ids "$ids" \
  '{displayName: $name, changelog: $changelog, changelogType: "markdown", gameVersions: $ids, releaseType: "release"}')

echo "Uploading $zip to CurseForge project $CF_PROJECT_ID as game version $game_version $ids"
curl -sS --fail-with-body \
  -H "X-Api-Token: $CF_API_KEY" \
  --form-string "metadata=$metadata" \
  -F "file=@$zip" \
  "$api/projects/$CF_PROJECT_ID/upload-file"
echo
