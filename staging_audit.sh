#!/usr/bin/env bash
# staging_audit.sh <app> [app2 ...]  -- READ-ONLY: only reads logs/files, writes nothing.
# DAYS=7 (default) limits request counts to the last N days; last-hit/last-change are unrestricted.
BASE="${BASE:-/home/master/applications}"
DAYS="${DAYS:-7}"
[[ "$DAYS" =~ ^[0-9]+$ ]] && [ "$DAYS" -ge 1 ] || { echo "DAYS must be a positive integer" >&2; exit 1; }
[ $# -eq 0 ] && { echo "Usage: [DAYS=7] staging_audit.sh <app_name> [app_name2 ...]" >&2; exit 1; }
srv=$(hostname -s)
pat=$(for i in $(seq 0 $((DAYS-1))); do LC_ALL=C date -d "-$i day" +%d/%b/%Y; done | paste -sd'|')

printf 'server\tapp\turls\tlast_backend_hit\tlast_static_hit\treqs_%sd\twp_login_POSTs_%sd\tadmin_POSTs_%sd\tlast_file_change\n' "$DAYS" "$DAYS" "$DAYS"
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

  read -r n lg ad < <(zcat -f "$L"/backend_*.access.log* 2>/dev/null | grep -E "\[($pat):" | awk '
    {n++} $6=="\"POST"{ if($7~/wp-login/)l++; else if($7~/wp-admin/ && $7!~/admin-ajax/)a++ }
    END{print n+0,l+0,a+0}')

  fc=$(find . -type f -not -path '*/cache/*' -not -name '*.log' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -1)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$srv" "$app" "${urls:-NONE}" "${lb:-NONE}" "${ls_:-NONE}" "${n:-0}" "${lg:-0}" "${ad:-0}" "${fc:-NONE}"
done
