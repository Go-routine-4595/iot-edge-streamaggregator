#!/bin/sh
# Run once on the VM as root. Idempotent.
set -eu

NAME=iot
UID_N=2000
GID_N=2000

getent group "$GID_N" >/dev/null || groupadd -g "$GID_N" "$NAME"
getent passwd "$UID_N" >/dev/null || \
  useradd -u "$UID_N" -g "$GID_N" -r -M -s /usr/sbin/nologin "$NAME"

id "$NAME"