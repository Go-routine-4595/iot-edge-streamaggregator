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
mkdir -p /etc/nats
mkdir -p /etc/nats/certs

# EMQ and NATS working directroy ownership and access
chown -R "${TARGET_UID}:${TARGET_GID}" \
  "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/etc" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
chmod -R u+rwX,g+rwX \
  "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
chmod u+rw \
  "$EMQX_BASE_DIR/etc"

# NATS Cert in host
chmod o+r /etc/nats
chown -R "${TARGET_UID}:${TARGET_GID}" /etc/nats

# NATS device.env creation is it doesn't exist
[ -f /host/nats/devices.env ] || {
    echo 'EDGE_DOMAINS=' > /host/nats/devices.env
    chown "$TARGET_UID:$TARGET_GID" /host/nats/devices.env
}

ls -ld "$EMQX_BASE_DIR" "$EMQX_BASE_DIR/log" "$EMQX_BASE_DIR/etc" "$EMQX_BASE_DIR/data" "$NATS_BASE_DIR"
echo "-------------------------- host-init exiting --------------------------"