#!/usr/bin/env python3
"""iso/size.py - how big the live image will be, before building it.

    python3 iso/size.py [--branch latest|quarterly] [--top N]

Downloads FreeBSD's package catalogue (packagesite, about 10 MB), resolves
iso/packages.txt with all dependencies (the DRM meta packages pinned as
iso/build.sh does) and prints the download and installed sizes and the
largest packages, and an estimate of the ISO's size.

GitHub releases take files up to 2 GiB (2048 MiB). Real builds came out
about 510-545 MiB larger than the package download: FreeBSD's base system
and kernel, and ZFS compressing in 128 KB blocks where a package compresses
whole files, less what iso/build.sh's trim step removes. November 2026,
"latest": about 1560 MiB of packages gave a 2107 MiB ISO; the same without
NVIDIA's driver (its download had failed), about 1340 MiB, gave 1850 MiB.

Needs: python3, and tar that reads zstd (FreeBSD's tar does; on Linux
install zstd).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ISO_OVER_DOWNLOAD = 550 * 2**20     # ISO minus package download, measured (see above)
RELEASE_LIMIT = 2 * 2**30           # largest file in a GitHub release


def catalogue(branch):
    url = "https://pkg.freebsd.org/FreeBSD:15:amd64/%s/packagesite.pkg" % branch
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "packagesite.pkg")
        urllib.request.urlretrieve(url, path)
        data = subprocess.run(["tar", "-xOf", path, "packagesite.yaml"], check=True,
                              capture_output=True).stdout.decode()
    pk = {}
    for line in data.splitlines():
        o = json.loads(line)
        pk[o["name"]] = o
    return pk


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--branch", default="latest")
    ap.add_argument("--top", type=int, default=15)
    args = ap.parse_args()
    pk = catalogue(args.branch)
    with open(os.path.join(HERE, "packages.txt")) as f:
        names = [l.split("#")[0].strip() for l in f if l.split("#")[0].strip()]
    # as iso/build.sh: one DRM version for every driver
    drm = next((d for d in pk.get("drm-kmod", {}).get("deps", {}) if d.startswith("drm-") and d.endswith("-kmod")), None)
    if drm:
        v = drm[len("drm-"):-len("-kmod")]
        names = [drm if n == "drm-kmod" else ("nvidia-drm-%s-kmod" % v if n == "nvidia-drm-kmod" else n) for n in names]
    missing = [n for n in names if n not in pk]
    seen, todo = set(), [n for n in names if n in pk]
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        for d in pk[n].get("deps") or {}:
            if d in pk:
                todo.append(d)
            else:
                missing.append("%s (needed by %s)" % (d, n))
    dl = sum(pk[n]["pkgsize"] for n in seen)
    inst = sum(pk[n]["flatsize"] for n in seen)
    print("%d packages: %.2f GiB to download, %.2f GiB installed" % (len(seen), dl / 2**30, inst / 2**30))
    for n in sorted(seen, key=lambda n: -pk[n]["flatsize"])[:args.top]:
        print("  %7.0f MiB  %s" % (pk[n]["flatsize"] / 2**20, n))
    if missing:
        print("not in the '%s' branch: %s" % (args.branch, ", ".join(sorted(set(missing)))))
        return 1
    iso = dl + ISO_OVER_DOWNLOAD
    print("ISO: about %.0f MiB (a GitHub release file can be at most %.0f MiB)" % (iso / 2**20, RELEASE_LIMIT / 2**20))
    if iso > RELEASE_LIMIT - 50 * 2**20:
        print("warning: the ISO will probably be too large for a GitHub release; trim it or leave packages out")
    return 0


if __name__ == "__main__":
    sys.exit(main())
