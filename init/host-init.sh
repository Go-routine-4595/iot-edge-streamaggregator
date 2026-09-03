#!/bin/sh
set -eu
: "${TARGET_UID:?}" "${TARGET_GID:?}"

EMQX_BASE_DIR=/host/emqx
NATS_BASE_DIR=/host/nats

echo "-------------------------- host-init starting --------------------------"

# EMQ
mkdir -p \
  "$EMQX_BASE_DIR" \
  "$EMQX_BASE_DIR/log" \
  "$EMQX_BASE_DIR/etc" \
  "$EMQX_BASE_DIR/data"

# NATS
mkdir -p "$NATS_BASE_DIR"

chown -R "${TARGET_UID}:${TARGET_GID}" \
  "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/etc" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
chmod -R u+rwX,g+rwX \
  "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
chmod u+rw \
  "$EMQX_BASE_DIR/etc"

ls -ld "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/etc" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
echo "-------------------------- host-init exiting --------------------------"