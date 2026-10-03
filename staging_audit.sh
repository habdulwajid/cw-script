#!/usr/bin/env bash
# staging_audit.sh <app> [app2 ...]
#
# READ-ONLY traffic/activity audit for Cloudways apps (backend access logs).
# Writes nothing: no temp files, no heredocs, no `sort` (which can spill to /tmp),
# no redirects to files, find is used without -delete/-exec. Output goes to stdout/stderr only.
# (Reading files can still update atime depending on mount options.)
#
# Settings (environment variables):
#   DAYS=7          rolling window of the last N*24h for request counts
#   TOP=0           N > 0 adds the top-N client IPs and top-N URLs (real traffic, query string stripped)
#   DETAIL=0        1 = also list every real request in the window (buffered in memory)
#   DETAIL_MAX=0    cap on DETAIL rows per app (0 = unlimited)
#   ALL=0           1 = read every retained log (last-hit columns then reach beyond the window);
#                   default only reads logs modified inside the window, so last hits show NONE
#                   if nothing happened in the window
#   FILES=1         0 = skip the last_file_change scan (the slowest part on apps with many files)
#   BASE=/home/master/applications
#
# What counts as non-human ("noise"), each a regex. Unset = default, set to empty = disabled:
#   NOISE_IP   default: ^(127\.0\.0\.1|::1)$      matched against the client IP
#   NOISE_URL  default: wp-cron\.php               matched against the request URL
#   NOISE_UA   default: monitors / uptime / health checks / bots / crawlers / spiders (user agent)
#
# Usage: DAYS=7 TOP=10 ./staging_audit.sh app1 app2
# Requires: bash >= 4.4, GNU find/date, awk (mawk or gawk), zcat

set -u
export LC_ALL=C

BASE="${BASE:-/home/master/applications}"
DAYS="${DAYS:-7}"
TOP="${TOP:-0}"
DETAIL="${DETAIL:-0}"
DETAIL_MAX="${DETAIL_MAX:-0}"
ALL="${ALL:-0}"
FILES="${FILES:-1}"

DEF_NOISE_IP='^(127\.0\.0\.1|::1)$'
DEF_NOISE_URL='wp-cron\.php'
DEF_NOISE_UA='[Mm]onitor|[Uu]ptime|Pingdom|StatusCake|[Hh]ealth ?[Cc]heck|[Bb]ot/|[Cc]rawler|[Ss]pider'
NOISE_IP="${NOISE_IP-$DEF_NOISE_IP}"
NOISE_URL="${NOISE_URL-$DEF_NOISE_URL}"
NOISE_UA="${NOISE_UA-$DEF_NOISE_UA}"

for v in DAYS TOP DETAIL_MAX; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || { echo "$v must be a non-negative integer" >&2; exit 1; }
done
[ "$DAYS" -ge 1 ] || { echo "DAYS must be >= 1" >&2; exit 1; }
[ $# -eq 0 ] && { echo "Usage: [DAYS=7] [TOP=10] [DETAIL=1] $0 <app_name> [app_name2 ...]" >&2; exit 1; }

srv=$(hostname -s)
CUTOFF=$(date -d "-${DAYS} days" +%Y%m%d%H%M%S) || { echo "GNU date required" >&2; exit 1; }
MMIN=$((DAYS * 1440 + 60))   # only logs modified inside the window (+1h margin) can hold in-window lines

# Lowest CPU/IO priority so the audit does not compete with the apps
RUN=()
command -v nice   >/dev/null 2>&1 && RUN+=(nice -n 19)
command -v ionice >/dev/null 2>&1 && RUN+=(ionice -c3)

# One awk process per app does everything in a single pass over the logs.
# Kept in a plain single-quoted string (no single quotes inside) so no heredoc temp file is needed.
AWK_PROG='
function iso(k) {
  return substr(k,1,4) "-" substr(k,5,2) "-" substr(k,7,2) " " substr(k,9,2) ":" substr(k,11,2) ":" substr(k,13,2)
}
# Print the top n entries of arr without sort (selection by repeated max)
function top(arr, n, tag,    i, k, best, bk) {
  for (i = 1; i <= n; i++) {
    best = 0; bk = ""
    for (k in arr) if (arr[k] > best) { best = arr[k]; bk = k }
    if (bk == "") break
    printf "#TOP_%s\t%s\t%s\t%d\n", tag, app, bk, best
    delete arr[bk]
  }
}
function scan(f,    dom, cmd, line, t, mm, key, inwin, real, u2, q, r, sp) {
  dom = f; sub(/.*\//, "", dom); sub(/^backend_/, "", dom); sub(/\.access\.log.*$/, "", dom)
  if (index(f, "\047")) return
  cmd = "zcat -f -- \047" f "\047 2>/dev/null"
  while ((cmd | getline line) > 0) {
    $0 = line
    t = substr($4, 2); mm = substr(t, 4, 3)
    if (substr($4, 1, 1) != "[" || !(mm in mon)) { bad++; continue }
    key = substr(t,8,4) mon[mm] substr(t,1,2) substr(t,13,2) substr(t,16,2) substr(t,19,2)
    if (key > lastany) lastany = key
    inwin = (key >= cut)
    if (inwin) { raw++; if ($1 == "127.0.0.1" || $1 == "::1") lo++ }
    if (!inwin && key <= lastreal) continue          # cannot change any output, skip noise test

    real = 1
    if (nip != "" && $1 ~ nip) real = 0
    else if (nurl != "" && $7 ~ nurl) real = 0
    else if (nua != "") { split($0, q, "\""); if (q[6] ~ nua) real = 0 }

    if (real && key > lastreal) lastreal = key
    if (inwin && real) {
      rl++
      if ($6 == "\"POST") {
        if ($7 ~ /wp-login/) lg++
        else if ($7 ~ /wp-admin/ && $7 !~ /admin-ajax/) ad++
      }
      if (top_n > 0) { ipc[$1]++; u2 = $7; sub(/\?.*/, "", u2); urlc[u2]++ }
      if (detail) {
        if (dmax == 0 || nd < dmax) {
          split($0, q, "\""); split(q[2], r, " "); split(q[3], sp, " ")
          nd++
          d[nd] = sprintf("#DETAIL\t%s\t%s\t%s\t%s\t%s\thttps://%s%s\t%s", app, iso(key), $1, r[1], sp[1], dom, r[2], q[6])
        } else dtrunc = 1
      }
    }
  }
  close(cmd)
}
BEGIN {
  app = ENVIRON["APP"]; srv = ENVIRON["SRV"]; cut = ENVIRON["CUTOFF"] ""
  top_n = ENVIRON["TOP"] + 0; detail = ENVIRON["DETAIL"] + 0; dmax = ENVIRON["DETAIL_MAX"] + 0
  nip = ENVIRON["NOISE_IP"]; nurl = ENVIRON["NOISE_URL"]; nua = ENVIRON["NOISE_UA"]
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mn, " ")
  for (i = 1; i <= 12; i++) mon[mn[i]] = sprintf("%02d", i)
  lastany = ""; lastreal = ""

  for (i = 1; i < ARGC; i++) scan(ARGV[i])

  printf "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s\n", srv, app, ENVIRON["DOMAINS"], \
    (lastreal == "" ? "NONE" : iso(lastreal)), (lastany == "" ? "NONE" : iso(lastany)), \
    raw + 0, rl + 0, lg + 0, ad + 0, ENVIRON["FC"]

  if (raw >= 20 && lo * 10 >= raw * 9)
    printf "WARNING: %s: %d%% of requests come from loopback, so the log shows the proxy, not the visitor. IP data and the real/raw split are unreliable.\n", app, lo * 100 / raw > "/dev/stderr"
  if (bad > 0) printf "NOTE: %s: %d unparseable log lines skipped\n", app, bad > "/dev/stderr"

  if (top_n > 0) { top(ipc, top_n, "IP"); top(urlc, top_n, "URL") }
  if (detail && nd > 0) {
    print "#DETAIL\tapp\ttime\tip\tmethod\tstatus\turl\tuser_agent"
    for (i = 1; i <= nd; i++) print d[i]
    if (dtrunc) printf "NOTE: %s: DETAIL truncated at %d rows\n", app, dmax > "/dev/stderr"
  }
}
'

printf 'server\tapp\tdomains\tlast_real_hit\tlast_any_hit\traw_reqs_%sd\treal_reqs_%sd\twp_login_POSTs\tadmin_POSTs\tlast_file_change\n' "$DAYS" "$DAYS"
printf '#META\tgenerated=%s\twindow_from=%s\twindow_days=%s\tscope=backend access logs only (origin hits; cache/static hits not included)\tscan=%s\n' \
  "$(date '+%F %T %Z')" "$CUTOFF" "$DAYS" "$([ "$ALL" = 1 ] && echo all-retained-logs || echo window-only)"

for app in "$@"; do
  [[ "$app" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Skipping invalid app name: $app" >&2; continue; }
  A="$BASE/$app"; L="$A/logs"; P="$A/public_html"
  [ -d "$P" ] || { printf '%s\t%s\tNOT_FOUND\n' "$srv" "$app"; continue; }

  domains=$(find "$L" -maxdepth 1 -type f \( -name 'backend_*.access.log*' -o -name 'static_*.access.log*' \) -printf '%f\n' 2>/dev/null \
    | sed -nE 's/^(backend|static)_(.*)\.access\.log.*/\2/p' | awk '!s[$0]++' | paste -sd, -)

  fc=""
  if [ "$FILES" = 1 ]; then
    fc=$(find "$P" -name cache -type d -prune -o -type f ! -name '*.log' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null \
      | awk 'NR==1 || $0>m {m=$0} END{print m}')
  fi

  fargs=(-maxdepth 1 -type f -name 'backend_*.access.log*')
  [ "$ALL" = 1 ] || fargs+=(-mmin "-$MMIN")
  mapfile -d '' -t files < <(find "$L" "${fargs[@]}" -print0 2>/dev/null)

  APP="$app" SRV="$srv" CUTOFF="$CUTOFF" TOP="$TOP" DETAIL="$DETAIL" DETAIL_MAX="$DETAIL_MAX" \
  DOMAINS="${domains:-NONE}" FC="${fc:-NONE}" \
  NOISE_IP="$NOISE_IP" NOISE_URL="$NOISE_URL" NOISE_UA="$NOISE_UA" \
    ${RUN[@]+"${RUN[@]}"} awk "$AWK_PROG" ${files[@]+"${files[@]}"}
done
