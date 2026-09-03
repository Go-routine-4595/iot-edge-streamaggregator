#!/bin/sh

set -eu
: "${TARGET_UID:?}" "${TARGET_GID:?}"

ETC=/host/etc            # bind mount of the host's /opt/emqx/etc
SRC=/opt/emqx/etc        # the image's own defaults (untouched inside this container)
SEED=/seed/emqx.conf     # the copy tracked in git

echo "-------------------------- emqx-init starting --------------------------"

mkdir -p "$ETC"

if [ -n "$(ls -A "$ETC" 2>/dev/null)" ]; then
  echo "$ETC already populated - leaving it alone"
else
  echo "$ETC is empty - seeding defaults from emqx/emqx:6.3.0"
  cp -a "$SRC/." "$ETC/"
  cp -f "$SEED" "$ETC/emqx.conf"
  chown -R "${TARGET_UID}:${TARGET_GID}" "$ETC"
fi

ls -la "$ETC"
echo "-------------------------- emqx-init exiting --------------------------"