#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for suite in oo generate trace validate; do
  bash "$DIR/${suite}.sh" || rc=1
done
exit $rc
