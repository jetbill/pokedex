#!/usr/bin/env bash
# Prueba de humo posterior al despliegue.
# Uso: bash scripts/smoke-test.sh <url-base> [reintentos=12] [espera_seg=15]
# El plan gratuito F1 duerme la app tras un rato sin tráfico: el primer arranque puede tardar
# uno o dos minutos, por eso se reintenta /healthz antes de dar la prueba por fallida.
set -euo pipefail

URL="${1:?Uso: smoke-test.sh <url-base> [reintentos] [espera_seg]}"
URL="${URL%/}"
RETRIES="${2:-12}"
SLEEP="${3:-15}"
FAILS=0

ok()   { echo "  [OK]    $1"; }
fail() { echo "  [FALLO] $1"; FAILS=$((FAILS + 1)); }

echo "== Esperando a que ${URL}/healthz responda 200 =="
READY=0
for i in $(seq 1 "$RETRIES"); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${URL}/healthz" || true)"
  if [ "$code" = "200" ]; then READY=1; break; fi
  echo "  intento ${i}/${RETRIES}: HTTP ${code:-000}"
  sleep "$SLEEP"
done
if [ "$READY" != "1" ]; then
  echo "ERROR: la aplicación no respondió 200 en /healthz tras ${RETRIES} intentos."
  exit 1
fi
ok "/healthz responde 200"

echo "== Comprobaciones funcionales =="
home="$(curl -s --max-time 30 "${URL}/" || true)"
if echo "$home" | grep -q '<app-root'; then ok "la portada contiene <app-root>"; else fail "la portada no contiene <app-root>"; fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${URL}/pokemon/25" || true)"
if [ "$code" = "200" ]; then ok "ruta profunda de la SPA (/pokemon/25) devuelve 200"; else fail "ruta profunda devuelve ${code}"; fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${URL}/no-existe-$$.js" || true)"
if [ "$code" = "404" ]; then ok "un archivo inexistente devuelve 404"; else fail "archivo inexistente devuelve ${code} (se esperaba 404)"; fi

if [[ "$URL" == https://* ]]; then
  HTTP_URL="http://${URL#https://}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${HTTP_URL}/" || true)"
  case "$code" in
    301|302|307|308) ok "HTTP redirige a HTTPS (${code})" ;;
    *) fail "HTTP no redirige a HTTPS (código ${code})" ;;
  esac
fi

if [ "$FAILS" -gt 0 ]; then
  echo "Prueba de humo FALLIDA: ${FAILS} comprobación(es)."
  exit 1
fi
echo "Prueba de humo superada."
