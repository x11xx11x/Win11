#!/usr/bin/env bash
# Downloads the official Windows 11 ISO from Microsoft straight onto the Ventoy stick.
# It only reads the partition list and writes one new file to the "Ventoy" partition.
# Works from an installed system or from a live ISO booted off the same Ventoy stick.
set -euo pipefail

# the whole script is read before anything runs, so "curl | bash" works
main() {
DIRECT="https://software.download.prss.microsoft.com/dbazure/Windows11_Client_x64_en-us_26300_9457.iso?t=24f9da11-6624-4f86-ade1-198d7bde4ed9&P1=1792942292&P2=602&P3=2&P4=BVRNoPqTBG8t8Ts5aw%2flst536TjVSzYS10cACt%2f3D7hMvvw8IFwFdM2W9AvnZiR0V9OQmFRT8faXhu2GWc8osUZR46M70nTnb34EGZwsA9GKPFh2xpFM6%2fhrSmoEUN1ZPVknorTvSKapG5QXai1ZFFsZu%2bcNULdFW1yWhc0Iyi9DITIu%2fylz%2fwOjXXRGvH0q5Fb5l3mJe0xls%2bcsl6yIwXVzkXSw%2fmGz0tLDy5MBIf7xzk3xxPYZ3q0vO4bK6dVdXt%2f39aaiscOIsT%2bqsCJMXgoMCo%2fVzioq7FLp%2b1f61zPSTgewG7Ny51NXT6acuROQKbfyhPk2PZugP%2f4fNs3%2fxw%3d%3d"
[[ ${1:-} == http* ]] && DIRECT=$1 && shift
LANG_NAME=${1:-English (United States)}
UA="Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
PAGE="https://www.microsoft.com/en-us/software-download/windows11"
PROFILE="606624d44113"

say() { echo -e "\e[32m::\e[0m $*"; }
die() { echo -e "\e[31mError:\e[0m $*" >&2; exit 1; }
root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

PART=$(lsblk -rpno PATH,LABEL,TYPE | awk '$2=="Ventoy" && $3=="part" {print $1; exit}')
[[ -n $PART ]] || die "No partition called Ventoy found. Plug in the Ventoy stick and try again."
DISK=$(lsblk -ndpo PKNAME "$PART")
[[ $(lsblk -ndo TRAN "$DISK") == usb ]] || die "$PART is not on a USB stick - stopping to be safe."
say "Ventoy partition: $PART on $DISK ($(lsblk -ndo SIZE,MODEL "$DISK" | xargs))"

# booted from this stick: Ventoy keeps the partition busy and exposes it as a device-mapper copy
DEV=$PART
SIZE=$(lsblk -ndbo SIZE "$PART")
for h in /sys/class/block/"${PART##*/}"/holders/*; do
    [[ -e $h ]] || continue
    if [[ $(( $(<"$h/size") * 512 )) == "$SIZE" ]]; then DEV=/dev/${h##*/}; fi
done
[[ $DEV != "$PART" ]] && say "Booted from this stick, using $DEV for the same partition"

MNT=$(lsblk -nro MOUNTPOINT "$DEV" | head -n1)
MOUNTED_HERE=0
if [[ -z $MNT ]]; then
    MNT=/mnt/ventoy
    root mkdir -p "$MNT"
    root mount -o "uid=$(id -u),gid=$(id -g)" "$DEV" "$MNT" || die "Could not mount $DEV."
    MOUNTED_HERE=1
fi
cleanup() { sync; if (( MOUNTED_HERE )); then root umount "$MNT" && say "Stick unmounted."; fi; }
trap cleanup EXIT

FREE=$(df --output=avail -B1G "$MNT" | tail -n1 | tr -d ' ')
(( FREE >= 8 )) || die "Only ${FREE} GB free on the stick, Windows 11 needs about 7 GB."
say "$FREE GB free on the stick"

URL=""
if [[ -n $DIRECT ]] && curl -fsI -o /dev/null -A "$UA" "$DIRECT"; then
    URL=$DIRECT
    say "Using the download link from the browser"
else
[[ -n $DIRECT ]] && say "The saved link has expired, asking Microsoft for a new one"
say "Asking Microsoft for a download link ($LANG_NAME)"
SID=$(cat /proc/sys/kernel/random/uuid)
HTML=$(curl -fsSL -A "$UA" -H "Accept:" "$PAGE") || die "Could not open $PAGE - check the internet."
EDITION=$(grep -Eo '<option value="[0-9]+">Windows' <<<"$HTML" | head -n1 | tr -cd '0-9')
[[ -n $EDITION ]] || die "Microsoft changed their download page. Download it in a browser: $PAGE"
curl -fsS -A "$UA" -H "Accept:" -o /dev/null "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$SID" || true
SKUS=$(curl -fsS -A "$UA" "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$PROFILE&ProductEditionId=$EDITION&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$SID") \
    || die "Microsoft did not answer. Try again in a few minutes."
SKU=$(grep -o '{[^{}]*}' <<<"$SKUS" | grep -F -e "\"LocalizedLanguage\":\"$LANG_NAME\"" -e "\"Language\":\"$LANG_NAME\"" \
      | head -n1 | grep -o '"Id":"[^"]*"' | cut -d'"' -f4 || true)
if [[ -z $SKU ]]; then
    echo "Languages:"; grep -o '"LocalizedLanguage":"[^"]*"' <<<"$SKUS" | cut -d'"' -f4 | sed 's/^/  /'
    die "Language '$LANG_NAME' not found. Run again with one from the list, in quotes."
fi
LINKS=$(curl -fsS -A "$UA" --referer "$PAGE" "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$PROFILE&productEditionId=undefined&SKU=$SKU&friendlyFileName=undefined&Locale=en-US&sessionID=$SID" || true)
grep -q "Sentinel marked this request as rejected" <<<"$LINKS" && die "Microsoft blocked automatic downloads from your IP right now. Download it in a browser: $PAGE"
URL=$(grep -o '"Uri":"[^"]*"' <<<"$LINKS" | cut -d'"' -f4 | grep -i x64 | head -n1 | sed 's/\\u0026/\&/g' || true)
[[ -n $URL ]] || die "Microsoft gave no link. Download it in a browser: $PAGE"
fi

NAME=$(basename "${URL%%\?*}")
say "Downloading $NAME to the stick (about 7 GB)"
curl -fL -C - --progress-bar -A "$UA" -o "$MNT/$NAME.part" "$URL"
mv "$MNT/$NAME.part" "$MNT/$NAME"
say "Writing everything to the stick (can take a minute)…"
sync
say "Done: $NAME is on the Ventoy stick."
}
main "$@" </dev/tty
