#!/bin/bash
set -e

# ==============================================================================
# Antigravity CLI Remote-Control Entrypoint
# ==============================================================================

TOKEN_FILE="${HOME}/.gemini/jetski-standalone-oauth-token"
HUB_PORT="${HUB_PORT:-4400}"
INSTANCE_NAME="${INSTANCE_NAME:-vps-antigravity}"

# Ensure directories have proper permissions
mkdir -p "${HOME}/.gemini" "${HOME}/.antigravity" "${HOME}/.config/gh" "${HOME}/.composer" /workspace

# 1. Setup GitHub CLI authentication if token is provided
if [ -n "${GH_TOKEN:-}" ]; then
    export GH_TOKEN="${GH_TOKEN}"
    export GITHUB_TOKEN="${GH_TOKEN}"
elif [ -n "${GITHUB_TOKEN:-}" ]; then
    export GH_TOKEN="${GITHUB_TOKEN}"
    export GITHUB_TOKEN="${GITHUB_TOKEN}"
fi

# 2. Export Database variables so Laravel and scripts pick them up
export DB_CONNECTION="${DB_CONNECTION:-mysql}"
export DB_HOST="${DB_HOST:-db}"
export DB_PORT="${DB_PORT:-3306}"
export DB_DATABASE="${DB_DATABASE:-laravel}"
export DB_USERNAME="${DB_USERNAME:-laravel_user}"
export DB_PASSWORD="${DB_PASSWORD:-secret}"

# 3. Command execution routing
case "$1" in
    login)
        echo "======================================================================"
        echo " 🔐  Autenticación inicial de Google Antigravity CLI"
        echo "======================================================================"
        echo "Se iniciará el proceso de login interactivo."
        echo "1. Abre en tu navegador la URL que aparecerá en pantalla."
        echo "2. Autoriza tu cuenta de Google."
        echo "3. Si se solicita un código, pégalo en esta terminal."
        echo "======================================================================"
        echo ""
        exec agy --remote-control --hub-port "$HUB_PORT" --remote-control-name "$INSTANCE_NAME"
        ;;

    status)
        echo "Consultando estado del daemon de Antigravity..."
        exec agy remote-control status
        ;;

    daemon|"")
        shift 2>/dev/null || true
        if [ ! -s "$TOKEN_FILE" ]; then
            echo "======================================================================"
            echo " ⚠️  AVISO DE AUTENTICACIÓN REQUERIDA"
            echo "======================================================================"
            echo " No se encontró el token de autenticación en:"
            echo " $TOKEN_FILE"
            echo ""
            echo " Para iniciar sesión por primera vez desde tu VPS, ejecuta:"
            echo "   docker compose run --rm antigravity-daemon login"
            echo ""
            echo " O si ya tienes Antigravity configurado en tu máquina local, copia tus"
            echo " credenciales desde ~/.gemini a este volumen persistente."
            echo "======================================================================"
            echo ""
        fi

        echo "🚀 Iniciando Antigravity CLI Daemon..."
        echo "   Nombre de instancia: $INSTANCE_NAME"
        echo "   Puerto Hub:          $HUB_PORT"
        echo "   Acceso Web:          https://antigravity.google (Remote Control)"
        echo ""

        exec agy --remote-control --hub-port "$HUB_PORT" --remote-control-name "$INSTANCE_NAME" "$@"
        ;;

    *)
        # If user passed custom flags or commands (e.g. bash, composer, php, agy)
        exec "$@"
        ;;
esac
