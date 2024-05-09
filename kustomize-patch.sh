#!/bin/bash

INF=$1
TMPF=$(mktemp)

cat "${INF}" > "${TMPF}"

# TODO: why does quoting the tempfile not work?
"${EDITOR:-vi}" ${TMPF}

PATCHES=$(jd -f patch -yaml ${INF} ${TMPF} | yq -P)

echo "patches:"
echo "${PATCHES}"
