#!/usr/bin/env bash
# Verifica las cabeceras de seguridad HTTP de una URL desplegada.
# Uso: bash scripts/verify-headers.sh <url>
set -euo pipefail

URL="${1:?Uso: verify-headers.sh <url>}"
FAILS=0

HEADERS="$(curl -sSI --max-time 30 "$URL" | tr -d '\r')"
status="$(printf '%s\n' "$HEADERS" | head -n1)"
echo "Respuesta: ${status}"

get() { printf '%s\n' "$HEADERS" | grep -i "^$1:" | head -n1 | cut -d: -f2- | sed 's/^ *//' || true; }
ok()   { echo "  [OK]    $1"; }
fail() { echo "  [FALLO] $1"; FAILS=$((FAILS + 1)); }

hsts="$(get strict-transport-security)"
if [[ "$hsts" =~ max-age=([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -ge 15552000 ]; then
  ok "Strict-Transport-Security: ${hsts}"
else
  fail "Strict-Transport-Security ausente o max-age < 15552000 (valor: '${hsts}')"
fi

csp="$(get content-security-policy)"
if [ -z "$csp" ]; then
  fail "Content-Security-Policy ausente"
else
  ok "Content-Security-Policy presente"
  [[ "$csp" == *"default-src"* ]]             && ok "  CSP define default-src"                 || fail "  CSP sin default-src"
  [[ "$csp" == *"frame-ancestors 'none'"* ]]  && ok "  CSP define frame-ancestors 'none'"      || fail "  CSP sin frame-ancestors 'none'"
  [[ "$csp" == *"object-src 'none'"* ]]       && ok "  CSP define object-src 'none'"          || fail "  CSP sin object-src 'none'"
  [[ "$csp" != *"'unsafe-eval'"* ]]           && ok "  CSP sin 'unsafe-eval'"                  || fail "  CSP contiene 'unsafe-eval'"
  script_src="$(printf '%s' "$csp" | tr ';' '\n' | sed 's/^ *//' | grep '^script-src' || true)"
  [[ "$script_src" != *"'unsafe-inline'"* ]]  && ok "  script-src sin 'unsafe-inline'"         || fail "  script-src contiene 'unsafe-inline'"
fi

xcto="$(get x-content-type-options)"
[ "${xcto,,}" = "nosniff" ] && ok "X-Content-Type-Options: ${xcto}" || fail "X-Content-Type-Options debe ser nosniff (valor: '${xcto}')"

xfo="$(get x-frame-options)"
case "${xfo^^}" in
  DENY|SAMEORIGIN) ok "X-Frame-Options: ${xfo}" ;;
  *) fail "X-Frame-Options debe ser DENY o SAMEORIGIN (valor: '${xfo}')" ;;
esac

rp="$(get referrer-policy)"
case "${rp,,}" in
  no-referrer|same-origin|strict-origin|strict-origin-when-cross-origin) ok "Referrer-Policy: ${rp}" ;;
  *) fail "Referrer-Policy ausente o débil (valor: '${rp}')" ;;
esac

pp="$(get permissions-policy)"
[ -n "$pp" ] && ok "Permissions-Policy presente" || fail "Permissions-Policy ausente"

coop="$(get cross-origin-opener-policy)"
[ -n "$coop" ] && ok "Cross-Origin-Opener-Policy: ${coop}" || fail "Cross-Origin-Opener-Policy ausente"

if [ -n "$(get x-powered-by)" ]; then fail "X-Powered-By expone la tecnología del servidor"; else ok "Sin X-Powered-By"; fi

if [ "$FAILS" -gt 0 ]; then
  echo "Verificación de cabeceras FALLIDA: ${FAILS} problema(s)."
  exit 1
fi
echo "Verificación de cabeceras superada."
