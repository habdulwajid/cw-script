#!/usr/bin/env bash
# staging_audit.sh <app> [app2 ...]  -- READ-ONLY: only reads logs/files, writes nothing.
BASE="${BASE:-/home/master/applications}"
[ $# -eq 0 ] && { echo "Usage: staging_audit.sh <app_name> [app_name2 ...]" >&2; exit 1; }
srv=$(hostname -s)

printf 'server\tapp\turls\tlast_backend_hit\tlast_static_hit\tbackend_reqs\twp_login_POSTs\tadmin_POSTs\tlast_file_change\n'
for app in "$@"; do
  [[ "$app" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Skipping invalid app name: $app" >&2; continue; }
  cd "$BASE/$app/public_html" 2>/dev/null || { printf '%s\t%s\tNOT_FOUND\n' "$srv" "$app"; continue; }
  L=../logs

  urls=$(ls "$L" 2>/dev/null | sed -nE 's/^(backend|static)_(.*)\.access\.log.*/\2/p' | sort -u | paste -sd, -)

  lasthit() {
    local f; f=$(ls -t "$L"/"$1"_*.access.log* 2>/dev/null | head -1)
    [ -z "$f" ] && { echo NONE; return; }
    zcat -f "$f" 2>/dev/null | tail -1 | grep -oE '\[[0-9]{2}/[A-Za-z]{3}/[0-9]{4}:[0-9:]{8} [+-][0-9]{4}' | tr -d '[' || echo NONE
  }
  lb=$(lasthit backend); ls_=$(lasthit static)

  read -r n lg ad < <(zcat -f "$L"/backend_*.access.log* 2>/dev/null | awk '
    {n++} $6=="\"POST"{ if($7~/wp-login/)l++; else if($7~/wp-admin/ && $7!~/admin-ajax/)a++ }
    END{print n+0,l+0,a+0}')

  fc=$(find . -type f -not -path '*/cache/*' -not -name '*.log' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -1)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$srv" "$app" "${urls:-NONE}" "${lb:-NONE}" "${ls_:-NONE}" "$n" "$lg" "$ad" "${fc:-NONE}"
done
