#!/usr/bin/env bash
# Downloads the official Windows 11 ISO from Microsoft straight onto the Ventoy stick.
# It only reads the stick's partition list and writes one file to the "Ventoy" partition.
set -euo pipefail

# the whole script is read before anything runs, so "curl | bash" works
main() {

LANG_NAME=${1:-English (United States)}
UA="Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
PAGE="https://www.microsoft.com/en-us/software-download/windows11"
PROFILE="606624d44113"

say() { echo -e "\e[32m::\e[0m $*"; }
die() { echo -e "\e[31mError:\e[0m $*" >&2; exit 1; }

for p in curl jq uuidgen; do
    command -v "$p" >/dev/null || { say "Installing $p"; sudo pacman -S --needed --noconfirm "${p/uuidgen/util-linux}"; }
done

PART=$(lsblk -rpno PATH,LABEL | awk '$2=="Ventoy" {print $1; exit}')
[[ -n $PART ]] || die "No partition called Ventoy found. Plug in the Ventoy stick and try again."
DISK=$(lsblk -rpno PKNAME "$PART")
[[ $(lsblk -dno TRAN "$DISK") == usb ]] || die "$PART is not on a USB stick - stopping to be safe."
say "Ventoy partition: $PART ($(lsblk -dno SIZE,MODEL "$DISK" | xargs))"

MNT=$(lsblk -rno MOUNTPOINT "$PART" | head -n1)
MOUNTED_HERE=0
if [[ -z $MNT ]]; then
    MNT=/mnt/ventoy
    sudo mkdir -p "$MNT"
    sudo mount -o "uid=$(id -u),gid=$(id -g)" "$PART" "$MNT"
    MOUNTED_HERE=1
fi
cleanup() { sync; if (( MOUNTED_HERE )); then sudo umount "$MNT" && say "Stick unmounted, you can pull it out."; fi; }
trap cleanup EXIT

FREE=$(df --output=avail -B1G "$MNT" | tail -n1 | tr -d ' ')
(( FREE >= 8 )) || die "Only ${FREE} GB free on the stick, Windows 11 needs about 7 GB."

say "Asking Microsoft for a download link ($LANG_NAME)"
SID=$(uuidgen)
HTML=$(curl -fsSL -A "$UA" -H "Accept:" "$PAGE")
EDITION=$(grep -Eo '<option value="[0-9]+">Windows' <<<"$HTML" | head -n1 | tr -cd '0-9')
[[ -n $EDITION ]] || die "Microsoft changed their download page. Download it in a browser: $PAGE"
curl -fsS -A "$UA" -H "Accept:" -o /dev/null "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$SID"
SKUS=$(curl -fsS -A "$UA" "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$PROFILE&ProductEditionId=$EDITION&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$SID")
SKU=$(jq -r --arg l "$LANG_NAME" '.Skus[] | select(.LocalizedLanguage==$l or .Language==$l) | .Id' <<<"$SKUS" | head -n1)
if [[ -z $SKU ]]; then
    echo "Languages:"; jq -r '.Skus[].LocalizedLanguage' <<<"$SKUS" | sed 's/^/  /'
    die "Language '$LANG_NAME' not found. Run again with one from the list, in quotes."
fi
LINKS=$(curl -fsS -A "$UA" --referer "$PAGE" "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$PROFILE&productEditionId=undefined&SKU=$SKU&friendlyFileName=undefined&Locale=en-US&sessionID=$SID")
grep -q "Sentinel marked this request as rejected" <<<"$LINKS" && die "Microsoft blocked automatic downloads from your IP right now. Download it in a browser: $PAGE"
URL=$(jq -r '.ProductDownloadOptions[].Uri' <<<"$LINKS" 2>/dev/null | grep x64 | head -n1 || true)
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
