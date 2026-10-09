#!/bin/bash
set -e

# ==============================================================================
# Antigravity CLI Remote-Control Entrypoint (Coolify / Railpack)
# ==============================================================================

# Add locally installed binaries (agy, gh) to PATH
export PATH="/app/.bin:$PATH"

# Directorio base para persistencia (en Coolify, puedes montar un volumen aquí)
PERSISTENT_DIR="${PERSISTENT_DIR:-/app/data}"

TOKEN_FILE="${PERSISTENT_DIR}/.gemini/jetski-standalone-oauth-token"
HUB_PORT="${HUB_PORT:-4400}"
INSTANCE_NAME="${INSTANCE_NAME:-coolify-antigravity}"

# Ensure directories have proper permissions
mkdir -p "${PERSISTENT_DIR}/.gemini" "${PERSISTENT_DIR}/.antigravity" "${PERSISTENT_DIR}/.config/gh" "${PERSISTENT_DIR}/.composer" /app/workspace

# Set environment variables for tools to use the persistent directory
export HOME="${PERSISTENT_DIR}"
export COMPOSER_HOME="${PERSISTENT_DIR}/.composer"

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
export DB_HOST="${DB_HOST:-127.0.0.1}"
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
        # Usamos un puerto diferente (HUB_PORT + 1) para no colisionar con el daemon principal
        exec agy --remote-control --hub-port "$((HUB_PORT + 1))" --remote-control-name "$INSTANCE_NAME"
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
            echo " Para iniciar sesión, abre la terminal del contenedor en Coolify y ejecuta:"
            echo "   bash ./entrypoint.sh login"
            echo ""
            echo " O si ya tienes Antigravity configurado, pega tus credenciales en el"
            echo " volumen persistente ($PERSISTENT_DIR/.gemini)."
            echo "======================================================================"
            echo ""
        fi

        # Auto-clone repositories if defined
        if [ -n "${CLONE_REPOSITORIES:-}" ]; then
            TARGET_BRANCH="${TARGET_BRANCH:-antigravity}"
            echo "📦 Configurando repositorios en /app/workspace (Rama objetivo: $TARGET_BRANCH)..."
            cd /app/workspace
            
            # Separar por comas
            IFS=',' read -r -a REPO_ARRAY <<< "$CLONE_REPOSITORIES"
            for REPO in "${REPO_ARRAY[@]}"; do
                # Eliminar espacios en blanco
                REPO="$(echo -e "${REPO}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                if [ -n "$REPO" ]; then
                    # Extraer el nombre del repositorio
                    REPO_NAME=$(basename "$REPO" .git)
                    if [ ! -d "$REPO_NAME" ]; then
                        echo "   ⬇️ Clonando $REPO..."
                        gh repo clone "$REPO" "$REPO_NAME" 2>/dev/null || git clone "$REPO" "$REPO_NAME" || echo "   ⚠️ Error al clonar $REPO"
                    else
                        echo "   ✅ El repositorio $REPO_NAME ya existe, saltando clonación."
                    fi
                    
                    if [ -d "$REPO_NAME" ]; then
                        echo "   🔄 Configurando rama $TARGET_BRANCH en $REPO_NAME..."
                        cd "$REPO_NAME"
                        git config pull.rebase false
                        git fetch --all --prune || true
                        # Intentar moverse a la rama, si no existe, crearla
                        git checkout "$TARGET_BRANCH" 2>/dev/null || git checkout -b "$TARGET_BRANCH"
                        cd ..
                    fi
                fi
            done
            cd /app
        fi

        # Start MariaDB server
        echo "🗄️ Starting MariaDB Server..."
        service mariadb start || echo "⚠️ Failed to start MariaDB service."
        
        # Give it a moment to initialize
        sleep 3
        
        # Create database and user
        echo "🛠️ Configuring Database ${DB_DATABASE} for user ${DB_USERNAME}..."
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\`;" || true
        mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';" || true
        mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'%';" || true
        mysql -u root -e "FLUSH PRIVILEGES;" || true

        echo "🚀 Iniciando Antigravity CLI Daemon..."
        echo "   Nombre de instancia: $INSTANCE_NAME"
        echo "   Puerto Hub:          $HUB_PORT"
        echo "   Acceso Web:          https://antigravity.google (Remote Control)"
        echo ""

        exec agy --remote-control --hub-port "$HUB_PORT" --remote-control-name "$INSTANCE_NAME" "$@"
        ;;

    *)
        # If user passed custom flags or commands
        exec "$@"
        ;;
esac
