#!/bin/sh
set -eu

# -----------------------------------------------------------------------------
# Central NATS stream setup: INFERENCE and ALERTS as SOURCE-ONLY streams.
#
# These streams have NO "subjects" field -- they are fed purely by cross-domain
# JetStream sources, one per edge device.
#
# This REPLACES the previous subject-based capture; it is not added alongside
# it. With subjects and no sources (the previous config) each message was
# stored once, via the live leaf flow -- there was no duplication, but nothing
# replayed what an outage missed. With sources and no subjects each message is
# stored once, via the source, AND is replayed after a reconnect.
#
# The configuration to avoid is BOTH at once: a stream carrying "subjects" AND
# "sources" receives every message twice, by two independent routes that know
# nothing about each other, and JetStream will not dedup them.
#
# The replay window is governed by the EDGE stream retention (INFERENCE is
# max-age 1h), not by the limits set here. An outage longer than the edge's
# max-age loses events permanently.
#
# Device list: EDGE_DOMAINS in /opt/nats/devices.env (host state, not in git).
# Add a device by appending its JetStream DOMAIN -- not its server_name -- and
# re-running just this one-shot:
#
#     docker compose run --rm nats-init
# -----------------------------------------------------------------------------

URL="${NATS_URL:-nats://nats:4222}"
EDGE_DOMAINS="${EDGE_DOMAINS:-}"

# Converting the previous subject-based streams to source-based cannot be done
# in place. Set RECREATE=1 for the single cutover run; it DELETES the streams
# and everything in them. Never leave it set.
RECREATE="${RECREATE:-0}"

fail() { echo "FATAL: $*" >&2; exit 1; }

echo "-------------------------- nats-init starting --------------------------"

[ -n "$EDGE_DOMAINS" ] || fail "EDGE_DOMAINS is empty (see /opt/nats/devices.env); nothing to source from."
echo "Edge domains: $EDGE_DOMAINS"

# --- bounded wait for JetStream ---------------------------------------------
i=0
until nats --server "$URL" stream ls >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "ERROR: JetStream not answering on $URL after ${i}s" >&2
        nats --server "$URL" stream ls || true      # surface the real error
        exit 1
    fi
    sleep 1
done
[ "$i" -gt 0 ] && echo "JetStream ready after ${i}s"

# --- preflight: fail loudly rather than half-configuring --------------------
# Both are needed: 'add' for the first run, 'edit' every time a device is
# appended to EDGE_DOMAINS later. Checking only 'add' would let a future CLI
# upgrade break the add-a-device path silently until the next device arrives.
for sub in add edit; do
    nats stream "$sub" --help 2>&1 | grep -q -- '--config' || fail \
"this nats CLI has no 'stream $sub --config'.
       Fallback: post the generated JSON straight at the API, e.g.
         nats req '\$JS.API.STREAM.CREATE.ALERTS' \"\$(cat /tmp/ALERTS.json)\"
       (STREAM.UPDATE.<name> for the edit path)"
done

# --- reachability report -----------------------------------------------------
# A source pointed at an unreachable domain is created without error and simply
# sits idle, so check explicitly rather than discovering it later.
# Checks the expected streams exist, not merely that the domain answers -- a
# device whose JetStream is up but whose own init.sh never ran would otherwise
# look healthy here and then source nothing.
for d in $EDGE_DOMAINS; do
    have=$(nats --server "$URL" --js-domain "$d" stream ls --json 2>/dev/null || echo '[]')
    if [ "$have" = "[]" ]; then
        echo "  WARNING  $d not reachable right now (device offline?)."
        echo "           Its sources are still created and catch up on return."
        continue
    fi
    for want in INFERENCE ALERTS; do
        if echo "$have" | jq -e --arg s "$want" 'index($s)' >/dev/null 2>&1; then
            echo "  ok       $d has $want"
        else
            echo "  WARNING  $d is reachable but has no $want stream."
            echo "           Its source for $want will be created and stay idle."
        fi
    done
done

# --- build a source-only stream config --------------------------------------
# The printf format strings are SINGLE-quoted so that $JS reaches the file
# literally instead of being expanded by the shell.
write_config() {
    NAME="$1"; MAX_AGE_NS="$2"; MAX_BYTES="$3"; OUT="$4"

    {
        printf '{\n'
        printf '  "name": "%s",\n'          "$NAME"
        printf '  "storage": "file",\n'
        printf '  "retention": "limits",\n'
        printf '  "discard": "old",\n'
        printf '  "max_age": %s,\n'         "$MAX_AGE_NS"
        printf '  "max_bytes": %s,\n'       "$MAX_BYTES"
        printf '  "max_msgs": -1,\n'
        printf '  "max_msg_size": -1,\n'
        printf '  "num_replicas": 1,\n'
        printf '  "sources": [\n'
        first=1
        for d in $EDGE_DOMAINS; do
            [ "$first" -eq 1 ] || printf ',\n'
            first=0
            printf '    {"name": "%s", "external": {"api": "$JS.%s.API", "deliver": ""}}' \
                   "$NAME" "$d"
        done
        printf '\n  ]\n'
        printf '}\n'
    } > "$OUT"
}

configure_stream() {
    NAME="$1"; MAX_AGE_NS="$2"; MAX_BYTES="$3"
    CFG="/tmp/${NAME}.json"

    write_config "$NAME" "$MAX_AGE_NS" "$MAX_BYTES" "$CFG"

    if nats --server "$URL" stream info "$NAME" >/dev/null 2>&1; then
        if [ "$RECREATE" = "1" ]; then
            echo "Recreating $NAME  (RECREATE=1 -- DISCARDS ITS MESSAGES)"
            nats --server "$URL" stream rm "$NAME" --force
            nats --server "$URL" stream add "$NAME" --config "$CFG"
        else
            echo "Updating $NAME"
            nats --server "$URL" stream edit "$NAME" --config "$CFG" --force
        fi
    else
        echo "Creating $NAME"
        nats --server "$URL" stream add "$NAME" --config "$CFG"
    fi
}

# max_age is NANOSECONDS in the stream config JSON. 24h = 86400000000000.
configure_stream INFERENCE 86400000000000 1073741824
configure_stream ALERTS    86400000000000 1073741824

# --- report -------------------------------------------------------------------
# "subjects" MUST be null/absent here. If it lists videoai.* the stream is
# capturing the live leaf flow as well as sourcing, and is storing everything
# twice.
for n in INFERENCE ALERTS; do
    echo "--- $n"
    nats --server "$URL" stream info "$n" --json \
        | jq '{subjects: .config.subjects,
               sources: [.config.sources[]? | .external.api],
               messages: .state.messages,
               bytes: .state.bytes}'
done

echo "-------------------------- nats-init exiting --------------------------"
