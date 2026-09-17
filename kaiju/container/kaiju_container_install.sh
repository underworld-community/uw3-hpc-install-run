#!/bin/bash
#
# Install a UW3 container into the shared location on Kaiju.
#
#   ./kaiju_container_install.sh development ghcr.io/jcgraciosa/underworld3-gadi:ci-gadi-container
#   ./kaiju_container_install.sh v3.2.0      ghcr.io/underworldcode/underworld3-gadi:v3.2.0
#
# No sudo: apptainer pull is unprivileged, so membership of uw3admin (which owns
# the destination directory) is sufficient. One-time setup:
#
#   sudo groupadd uw3admin
#   sudo usermod -aG uw3admin <user>
#   sudo mkdir -p /opt/cluster/software/containers/underworld3
#   sudo chgrp -R uw3admin /opt/cluster/software/containers/underworld3
#   sudo chmod 2775 /opt/cluster/software/containers/underworld3
#
# The 2 in 2775 is setgid, so files created by one member stay writable by the
# others.
#
# Files are never overwritten: each pull lands under a dated name and the channel
# symlink is swapped atomically. Apptainer memory-maps the SIF, so rewriting one
# in place would corrupt any job already running against it — whereas a symlink
# swap leaves running jobs on their original inode.
#
# A version channel (vX.Y.Z) also moves latest.sif, so users can follow the
# current release without editing their scripts.

set -euo pipefail

CHANNEL=${1:?usage: $0 <development|vX.Y.Z> <image-ref>}
IMAGE=${2:?usage: $0 <channel> <image-ref>}

DEST=/opt/cluster/software/containers/underworld3

[ -w "$DEST" ] || { echo "cannot write $DEST — are you in uw3admin?" >&2; exit 1; }
cd "$DEST"

# Pull to a scratch name first, then name the file after its own content. A
# date alone is not unique: two pulls on one day would overwrite in place, and
# overwriting a SIF corrupts any job that has it mapped.
TMP=".pull-$$.sif"
trap 'rm -f "$DEST/$TMP"' EXIT
apptainer pull --force --name "$TMP" "docker://${IMAGE}"

SHA=$(sha256sum "$TMP" | cut -d' ' -f1)
NAME="underworld3-${CHANNEL}-$(date +%Y%m%d)-${SHA:0:12}.sif"

if [ -e "$NAME" ]; then
    echo "identical image already present as $NAME — reusing it"
    rm -f "$TMP"
else
    mv -n "$TMP" "$NAME"
fi

# Refuse to publish an image that cannot import underworld3. Cheap, and it is
# the failure a rolling channel is most likely to pick up.
# OpenMPI's mlx4_0 probe warnings go to STDOUT, so restrict the transport for
# this single-process check and keep only the last line. pipefail still makes a
# genuine import failure fail the pipeline.
if ! VERSION=$(APPTAINERENV_OMPI_MCA_btl=self,vader \
        apptainer exec "$NAME" python3 -c \
        "import underworld3; print(underworld3.__version__)" 2>/dev/null | tail -1); then
    echo "FAILED: 'import underworld3' does not work in $NAME — not published" >&2
    echo "the file is left in place for inspection" >&2
    exit 1
fi

swap_link() {
    # ln -sfn unlinks first, leaving a window where the name does not resolve.
    ln -sfn "$1" ".$2.tmp"
    mv -Tf ".$2.tmp" "$2"
}

swap_link "$NAME" "${CHANNEL}.sif"
case "$CHANNEL" in
    v*) swap_link "$NAME" "latest.sif" ;;
esac

# Keep the last two of each channel. Local SIFs are a cache, not an archive:
# release images live under immutable tags in GHCR and CI never prunes tagged
# versions, so a pruned release can be re-pulled and verified against the
# sha256 in MANIFEST.
#
# A stale per-version symlink is removed with its target — otherwise the
# "skip anything symlinked" rule would protect every release forever.
prune_channel() {
    local glob=$1 keep=2 f l protected
    # latest.sif and development.sif always win; per-version links do not.
    protected=$(for l in latest.sif development.sif; do
                    [ -L "$l" ] && readlink "$l"
                done | sort -u)
    for f in $(ls -t $glob 2>/dev/null | tail -n +$((keep + 1))); do
        if grep -qxF "$f" <<<"$protected"; then continue; fi
        for l in *.sif; do
            [ -L "$l" ] && [ "$(readlink "$l")" = "$f" ] && rm -f "$l"
        done
        echo "pruned:     $f"
        rm -f "$f"
    done
}

printf '%s  %-44s  %-28s  %s  %s\n' \
    "$(date -Is)" "$NAME" "$VERSION" "${SHA:0:16}" "$IMAGE" >> MANIFEST

chmod a+rX "$NAME"

echo
echo "installed:  $DEST/$NAME"
echo "version:    $VERSION"
echo "sha256:     $SHA"
echo "channel:    ${CHANNEL}.sif -> $NAME"
case "$CHANNEL" in v*) echo "            latest.sif -> $NAME" ;; esac

prune_channel 'underworld3-development-*.sif'
prune_channel 'underworld3-v*.sif'

echo
echo "MANIFEST records every install; the last two of each channel are kept on disk."
echo "A pruned release can be re-pulled from GHCR and checked against its sha256."
