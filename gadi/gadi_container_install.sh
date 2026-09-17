#!/bin/bash
#
# Install a UW3 container into the shared location on Gadi. Run on a login node
# (compute nodes have no internet).
#
#   ./gadi_container_install.sh development ghcr.io/underworldcode/underworld3-gadi:development
#   ./gadi_container_install.sh v3.2.0      ghcr.io/underworldcode/underworld3-gadi:v3.2.0
#
# One-time setup. Every m18 member is in group m18 and there is no sub-group, so
# the directory is NOT group-writable; a second maintainer gets an ACL instead.
#
#   D=/g/data/m18/software/containers/underworld3
#   mkdir -p $D && chmod 2755 $D
#   setfacl -m u:<second-admin>:rwx -m d:u:<second-admin>:rwx $D
#   # adopt the existing hand-built image without moving it — the scaling
#   # campaign pins that path
#   cd $D
#   ln -s ../underworld3-gadi_v3.1.0.sif v3.1.0.sif
#   ln -s ../underworld3-gadi_v3.1.0.sif latest.sif
#   printf '%s  %-44s  %-28s  %s  %s\n' "$(date -Is)" ../underworld3-gadi_v3.1.0.sif \
#       0.99.0b "$(sha256sum ../underworld3-gadi_v3.1.0.sif | cut -c1-16)" hand-built >> MANIFEST
#
# Files are never overwritten: each pull lands under a content-addressed name,
# is made read-only, and the channel symlink is swapped atomically. Singularity
# memory-maps the SIF, so rewriting one in place would corrupt any job already
# running against it — a symlink swap leaves running jobs on their inode.
#
# A version channel (vX.Y.Z) also moves latest.sif.

CHANNEL=${1:?usage: $0 <development|vX.Y.Z> <image-ref>}
IMAGE=${2:?usage: $0 <channel> <image-ref>}

DEST=/g/data/m18/software/containers/underworld3

# Before set -u: the module function trips over unset variables.
module load singularity

set -euo pipefail

# $HOME is 10 GB; the OCI blobs plus the unpacked image are ~4 GB.
export SINGULARITY_CACHEDIR=/scratch/m18/$USER/.singularity
export SINGULARITY_TMPDIR=/scratch/m18/$USER/tmp
mkdir -p "$SINGULARITY_CACHEDIR" "$SINGULARITY_TMPDIR"

[ -w "$DEST" ] || { echo "cannot write $DEST — owner or ACL only (see header)" >&2; exit 1; }
cd "$DEST"

# Pull to a scratch name first, then name the file after its own content, so
# two pulls on one day cannot collide.
TMP=".pull-$$.sif"
trap 'rm -f "$DEST/$TMP"' EXIT
singularity pull --force --name "$TMP" "docker://${IMAGE}"

SHA=$(sha256sum "$TMP" | cut -d' ' -f1)
NAME="underworld3-${CHANNEL}-$(date +%Y%m%d)-${SHA:0:12}.sif"

if [ -e "$NAME" ]; then
    echo "identical image already present as $NAME — reusing it"
    rm -f "$TMP"
else
    mv -n "$TMP" "$NAME"
fi

# Refuse to publish an image that cannot import underworld3. MPI warnings go to
# stderr on Gadi; pipefail still fails the pipeline on a genuine import error.
if ! VERSION=$(singularity exec "$NAME" python3 -c \
        "import underworld3; print(underworld3.__version__)" 2>/dev/null | tail -1); then
    echo "FAILED: 'import underworld3' does not work in $NAME — not published" >&2
    echo "the file is left in place for inspection" >&2
    exit 1
fi

# Read-only: a stray `singularity pull --force` onto this name now fails instead
# of corrupting a running job. rm still works — that is a directory permission.
chmod 444 "$NAME"

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
# versions, so a pruned release can be re-pulled and verified against MANIFEST.
#
# A stale per-version symlink is removed with its target — otherwise the
# "skip anything symlinked" rule would protect every release forever.
prune_channel() {
    local glob=$1 keep=2 f l protected
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
