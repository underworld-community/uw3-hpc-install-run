#!/bin/bash
#
# Retry sbatch on transient controller-side failures.
#
# Kaiju intermittently returns "I/O error writing script/environment to file",
# which kills a submission chain part-way through. Cause not yet identified —
# disk, inodes, ownership and the logs were all clean when checked.
#
#   source sbatch_retry.sh
#   sbatch_retry --nodes=2 kaiju_container_job.sh
#
# SBATCH_TRIES (default 5) and SBATCH_DELAY (default 5s, doubling) tune it.

sbatch_retry() {
    local tries=${SBATCH_TRIES:-5}
    local delay=${SBATCH_DELAY:-5}
    local n=1 out

    while :; do
        if out=$(sbatch "$@" 2>&1); then
            echo "$out"
            return 0
        fi

        # Retry only failures that are the controller's fault. A bad partition
        # or account is permanent, and retrying it five times just delays the
        # error message you need to see.
        case "$out" in
            *"I/O error"*|*"Unable to contact slurm controller"*|\
            *"Socket timed out"*|*"Zero Bytes were transmitted"*)
                if [ "$n" -ge "$tries" ]; then
                    echo "sbatch failed after ${tries} attempts: $out" >&2
                    return 1
                fi
                echo "sbatch attempt ${n}/${tries} failed (${out}) — retrying in ${delay}s" >&2
                sleep "$delay"
                n=$((n + 1))
                delay=$((delay * 2))
                ;;
            *)
                echo "$out" >&2
                return 1
                ;;
        esac
    done
}

# Submit a dependency chain atomically: each step waits on the previous, and if
# any submission fails the already-queued steps are cancelled. A half-submitted
# chain otherwise runs its first jobs and silently stops.
#
#   sbatch_chain step1.sh step2.sh step3.sh
#   SBATCH_ARGS="--export=ALL,SCRIPT=model.py" sbatch_chain a.sh b.sh
#
# Prints the job IDs, one per line.

sbatch_chain() {
    local submitted=() prev="" id script

    for script in "$@"; do
        if [ -z "$prev" ]; then
            id=$(sbatch_retry --parsable ${SBATCH_ARGS:-} "$script")
        else
            id=$(sbatch_retry --parsable --kill-on-invalid-dep=yes \
                              --dependency=afterok:"$prev" ${SBATCH_ARGS:-} "$script")
        fi

        if [ -z "$id" ]; then
            echo "sbatch_chain: '${script}' failed to submit" >&2
            if [ ${#submitted[@]} -gt 0 ]; then
                echo "sbatch_chain: cancelling ${submitted[*]}" >&2
                scancel "${submitted[@]}"
            fi
            return 1
        fi

        submitted+=("$id")
        prev="$id"
    done

    printf '%s\n' "${submitted[@]}"
}
