#!/usr/bin/env bash
# Downloads the official Windows 11 ISO from Microsoft straight onto the Ventoy stick.
# It only reads the partition list and writes one new file to the "Ventoy" partition.
# Works from an installed system or from a live ISO booted off the same Ventoy stick.
set -euo pipefail

# the whole script is read before anything runs, so "curl | bash" works
main() {
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

NAME=$(basename "${URL%%\?*}")
say "Downloading $NAME to the stick (about 7 GB)"
curl -fL -C - --progress-bar -A "$UA" -o "$MNT/$NAME.part" "$URL"
mv "$MNT/$NAME.part" "$MNT/$NAME"
say "Writing everything to the stick (can take a minute)…"
sync
say "Done: $NAME is on the Ventoy stick."
}
main "$@" </dev/tty
