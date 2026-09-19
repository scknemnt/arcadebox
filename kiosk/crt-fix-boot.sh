#!/bin/sh
# Boot duzelt — crt-rollback ile ayni (geriye uyumluluk).
exec sh "$(dirname "$0")/crt-rollback.sh" "$@"
