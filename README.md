# Win11

Downloads the official Windows 11 ISO from Microsoft straight onto a Ventoy USB stick, from a Linux terminal (Arch).

```bash
curl -fsSL https://raw.githubusercontent.com/x11xx11x/Win11/main/w.sh | bash
```

Another language: `curl -fsSL https://raw.githubusercontent.com/x11xx11x/Win11/main/w.sh | bash -s -- "Romanian"`

It only writes one file to the partition labelled `Ventoy` on a USB disk. If Microsoft blocks the automated download, download the ISO in a browser from https://www.microsoft.com/software-download/windows11 instead.
