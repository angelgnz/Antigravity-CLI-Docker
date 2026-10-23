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
export DB_FRESH_SEED="${DB_FRESH_SEED:-true}"

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

        echo "======================================================================"
        echo " 📦 Instalando/Configurando Node.js via NVM..."
        echo "======================================================================"
        # Forzamos NVM_DIR para que use el volumen persistente de Coolify
        export NVM_DIR="$PERSISTENT_DIR/.nvm"
        
        # Solo descargamos nvm si no existe en el volumen persistente
        if [ ! -d "$NVM_DIR" ]; then
            echo "Descargando e instalando NVM..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
        fi
        
        echo "Cargando NVM en el entorno del script..."
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        echo "Instalando Node.js v24..."
        nvm install 24
        nvm use 24

        echo "Verificando instalación de Node..."
        node -v
        npm -v
        echo "======================================================================"

        # Start MariaDB server FIRST so migrations can run
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
                        echo "   ✅ El repositorio $REPO_NAME ya existe."
                    fi
                    
                    if [ -d "$REPO_NAME" ]; then
                        # Si el nombre del repo tiene mayúsculas (ej. Sirio), crear symlink en minúsculas (sirio)
                        # para que coincida siempre con el subdominio HTTP (que los navegadores envían en minúsculas)
                        REPO_LOWER="${REPO_NAME,,}"
                        if [ "$REPO_NAME" != "$REPO_LOWER" ] && [ ! -e "/app/workspace/$REPO_LOWER" ]; then
                            ln -sfn "/app/workspace/$REPO_NAME" "/app/workspace/$REPO_LOWER"
                        fi

                        echo "   🔄 Configurando $REPO_NAME..."
                        cd "/app/workspace/$REPO_NAME"
                        git config pull.rebase false
                        git fetch --all --prune || true
                        # Intentar moverse a la rama, si no existe, crearla
                        git checkout "$TARGET_BRANCH" 2>/dev/null || git checkout -b "$TARGET_BRANCH"
                        
                        # Instalar dependencias PHP
                        if [ -f "composer.json" ]; then
                            echo "   📦 Ejecutando composer install..."
                            if composer install --no-interaction; then
                                echo "   ✅ composer install exitoso."
                            else
                                echo "   ❌ Error en composer install."
                            fi
                        fi
                        
                        # Configurar .env ANTES de compilar JS (por si requiere variables VITE_)
                        if [ ! -f ".env" ] && [ -f ".env.example" ]; then
                            echo "   📝 Creando archivo .env..."
                            cp .env.example .env
                            # Inyectar credenciales de base de datos, descomentando si es necesario
                            sed -i "s/^[#]*[[:space:]]*DB_CONNECTION=.*/DB_CONNECTION=mysql/g" .env
                            sed -i "s/^[#]*[[:space:]]*DB_HOST=.*/DB_HOST=127.0.0.1/g" .env
                            sed -i "s/^[#]*[[:space:]]*DB_PORT=.*/DB_PORT=3306/g" .env
                            sed -i "s/^[#]*[[:space:]]*DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/g" .env
                            sed -i "s/^[#]*[[:space:]]*DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/g" .env
                            sed -i "s/^[#]*[[:space:]]*DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" .env
                            
                            # Inyectar variables adicionales desde Coolify si están definidas
                            if [ -n "${TURNSTILE_SITE_KEY:-}" ]; then sed -i "s|^[#]*[[:space:]]*TURNSTILE_SITE_KEY=.*|TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY}|g" .env; fi
                            if [ -n "${TURNSTILE_SECRET_KEY:-}" ]; then sed -i "s|^[#]*[[:space:]]*TURNSTILE_SECRET_KEY=.*|TURNSTILE_SECRET_KEY=${TURNSTILE_SECRET_KEY}|g" .env; fi
                            if [ -n "${GEOIP_DOWNLOAD_URL:-}" ]; then sed -i "s|^[#]*[[:space:]]*GEOIP_DOWNLOAD_URL=.*|GEOIP_DOWNLOAD_URL=${GEOIP_DOWNLOAD_URL}|g" .env; fi
                            if [ -n "${GEOIP_DB_PATH:-}" ]; then sed -i "s|^[#]*[[:space:]]*GEOIP_DB_PATH=.*|GEOIP_DB_PATH=${GEOIP_DB_PATH}|g" .env; fi
                            if [ -n "${MAXMIND_ACCOUNT_ID:-}" ]; then sed -i "s|^[#]*[[:space:]]*MAXMIND_ACCOUNT_ID=.*|MAXMIND_ACCOUNT_ID=${MAXMIND_ACCOUNT_ID}|g" .env; fi
                            if [ -n "${MAXMIND_LICENSE_KEY:-}" ]; then sed -i "s|^[#]*[[:space:]]*MAXMIND_LICENSE_KEY=.*|MAXMIND_LICENSE_KEY=${MAXMIND_LICENSE_KEY}|g" .env; fi
                        fi
                        
                        # Instalar dependencias JS y compilar assets
                        if [ -f "package.json" ]; then
                            echo "   🔍 Diagnosticando entorno Node.js:"
                            echo "      Ruta node: $(which node || echo 'not found')"
                            echo "      Versión node: $(node -v || echo 'error')"
                            echo "      Ruta npm: $(which npm || echo 'not found')"
                            echo "      Versión npm: $(npm -v || echo 'error')"
                            
                            echo "   📦 Ejecutando npm install..."
                            if npm install --include=dev --verbose; then
                                echo "   ✅ npm install exitoso."
                            else
                                echo "   ❌ Error en npm install."
                            fi
                            
                            echo "   🏗️ Compilando assets (npm run build)..."
                            if npm run build; then
                                echo "   ✅ assets compilados exitosamente."
                            else
                                echo "   ❌ Error en npm run build."
                            fi
                        fi
                        
                        # Tareas específicas de Laravel
                        if [ -f "artisan" ]; then
                            echo "   🔑 Verificando APP_KEY..."
                            if ! grep -E -q '^APP_KEY=[a-zA-Z0-9]' .env 2>/dev/null; then
                                php artisan key:generate --force || true
                            fi
                            
                            echo "   🧹 Limpiando cachés previas..."
                            php artisan optimize:clear || true

                            # 4. Publicar assets de Filament (ANTES de cualquier caché)
                            echo "   🎨 Publicando assets de Filament..."
                            php artisan filament:assets || true

                            # 5. Base de datos y Storage
                            echo "   🗃️ Base de datos y Storage..."
                            if [ "${DB_FRESH_SEED:-true}" = "true" ] || [ "${DB_FRESH_SEED:-true}" = "1" ]; then
                                echo "   🌱 Recreando base de datos y ejecutando seeders (migrate:fresh --seed)..."
                                php artisan migrate:fresh --seed --force || true
                            else
                                echo "   📦 Ejecutando migraciones pendientes (migrate)..."
                                php artisan migrate --force || true
                            fi
                            php artisan storage:link --force || true

                            # 6. Hook opcional por repositorio (.agy-init.sh) ANTES de cachear configuración
                            if [ -f "/app/workspace/$REPO_NAME/.agy-init.sh" ]; then
                                echo "   🧩 Ejecutando configuración específica (.agy-init.sh) para $REPO_NAME..."
                                if bash "/app/workspace/$REPO_NAME/.agy-init.sh"; then
                                    echo "   ✅ .agy-init.sh ejecutado correctamente."
                                else
                                    echo "   ⚠️ Error al ejecutar .agy-init.sh en $REPO_NAME (continuando el arranque)."
                                fi
                            fi

                            # 7. Caché y optimizaciones de producción
                            echo "   ⚡ Optimizando configuración, rutas, vistas y eventos..."
                            php artisan config:cache || true
                            php artisan route:cache || true
                            php artisan view:cache || true
                            php artisan event:cache || true
                            php artisan filament:optimize || true
                        elif [ -f "/app/workspace/$REPO_NAME/.agy-init.sh" ]; then
                            # Ejecutar hook opcional también si el repositorio no es Laravel
                            echo "   🧩 Ejecutando configuración específica (.agy-init.sh) para $REPO_NAME..."
                            if bash "/app/workspace/$REPO_NAME/.agy-init.sh"; then
                                echo "   ✅ .agy-init.sh ejecutado correctamente."
                            else
                                echo "   ⚠️ Error al ejecutar .agy-init.sh en $REPO_NAME (continuando el arranque)."
                            fi
                        fi

                        # Definir el primer repositorio con carpeta public como fallback por defecto
                        if [ -z "${DEFAULT_DOCUMENT_ROOT:-}" ] && [ -d "/app/workspace/$REPO_NAME/public" ]; then
                            export DEFAULT_DOCUMENT_ROOT="/app/workspace/$REPO_NAME/public"
                        fi
                        
                        cd /app/workspace
                    fi
                fi
            done
            cd /app
        fi

        # Si no se definió DEFAULT_DOCUMENT_ROOT (ej. repositorios previos en volumen), detectar el primero con /public
        if [ -z "${DEFAULT_DOCUMENT_ROOT:-}" ]; then
            FIRST_PUBLIC_DIR=$(find /app/workspace -maxdepth 2 -mindepth 2 -type d -name "public" 2>/dev/null | head -n 1 || true)
            if [ -n "$FIRST_PUBLIC_DIR" ]; then
                export DEFAULT_DOCUMENT_ROOT="$FIRST_PUBLIC_DIR"
            else
                export DEFAULT_DOCUMENT_ROOT="/app/workspace/default/public"
            fi
        fi

        # Iniciar servidor web único con FrankenPHP / Caddy (resolución dinámica por subdominio)
        export APP_PORT="${APP_PORT:-8000}"
        CADDYFILE_PATH="/app/Caddyfile"
        if [ ! -f "$CADDYFILE_PATH" ] && [ -f "/Caddyfile" ]; then
            CADDYFILE_PATH="/Caddyfile"
        fi

        if command -v frankenphp >/dev/null 2>&1 && [ -f "$CADDYFILE_PATH" ]; then
            echo "🌐 Iniciando servidor FrankenPHP (Caddy) dinámico en el puerto ${APP_PORT}..."
            echo "   Ruta por subdominio: https://{proyecto}.tudominio.com -> /app/workspace/{proyecto}/public"
            echo "   Fallback por defecto: ${DEFAULT_DOCUMENT_ROOT}"
            frankenphp run --config "$CADDYFILE_PATH" --adapter caddyfile > /var/log/frankenphp.log 2>&1 &
        elif command -v caddy >/dev/null 2>&1 && [ -f "$CADDYFILE_PATH" ]; then
            echo "🌐 Iniciando servidor Caddy dinámico en el puerto ${APP_PORT}..."
            caddy run --config "$CADDYFILE_PATH" --adapter caddyfile > /var/log/caddy.log 2>&1 &
        else
            echo "⚠️ FrankenPHP/Caddy no encontrado o sin Caddyfile; omitiendo servidor web."
        fi

        echo "🚀 Iniciando Antigravity CLI Daemon..."
        echo "   Nombre de instancia: $INSTANCE_NAME"
        echo "   Puerto Hub:          $HUB_PORT"
        echo "   Acceso Web:          https://antigravity.google (Remote Control)"
        echo ""

        # Cambiar el directorio de trabajo para que Antigravity inicie en el repositorio
        cd /app/workspace
        
        # Si hay exactamente un repositorio clonado (o una sola carpeta en workspace), entrar en ella
        # para que sea la raíz directa del agente en Remote Control
        DIR_COUNT=$(find . -maxdepth 1 -mindepth 1 -type d | wc -l)
        if [ "$DIR_COUNT" -eq 1 ]; then
            SINGLE_REPO=$(find . -maxdepth 1 -mindepth 1 -type d | head -n 1)
            echo "📂 Estableciendo $SINGLE_REPO como directorio raíz de Antigravity..."
            cd "$SINGLE_REPO"
        else
            echo "📂 Estableciendo /app/workspace como directorio raíz de Antigravity..."
        fi

        # Configuración granular de permisos y políticas de revisión
        RESOLVED_TOOL_PERMISSION="${TOOL_PERMISSION:-}"
        RESOLVED_ARTIFACT_POLICY="${ARTIFACT_REVIEW_POLICY:-}"

        if [ -n "${AUTO_APPROVE:-}" ]; then
            if [ "$AUTO_APPROVE" = "true" ] || [ "$AUTO_APPROVE" = "1" ]; then
                RESOLVED_TOOL_PERMISSION="${RESOLVED_TOOL_PERMISSION:-always-proceed}"
                RESOLVED_ARTIFACT_POLICY="${RESOLVED_ARTIFACT_POLICY:-always-proceed}"
            elif [ "$AUTO_APPROVE" = "false" ] || [ "$AUTO_APPROVE" = "0" ]; then
                RESOLVED_TOOL_PERMISSION="${RESOLVED_TOOL_PERMISSION:-request-review}"
                RESOLVED_ARTIFACT_POLICY="${RESOLVED_ARTIFACT_POLICY:-asks-for-review}"
            fi
        fi

        # Normalizar booleanos a las opciones soportadas por Antigravity
        case "$RESOLVED_TOOL_PERMISSION" in
            true|1)  RESOLVED_TOOL_PERMISSION="always-proceed" ;;
            false|0) RESOLVED_TOOL_PERMISSION="request-review" ;;
        esac

        case "$RESOLVED_ARTIFACT_POLICY" in
            true|1)  RESOLVED_ARTIFACT_POLICY="always-proceed" ;;
            false|0) RESOLVED_ARTIFACT_POLICY="asks-for-review" ;;
        esac

        EXTRA_ARGS=()
        if [ -n "$RESOLVED_TOOL_PERMISSION" ] || [ -n "$RESOLVED_ARTIFACT_POLICY" ]; then
            echo "⚙️ Configurando políticas de permisos de Antigravity:"
            if [ -n "$RESOLVED_TOOL_PERMISSION" ]; then
                echo "   - toolPermission: $RESOLVED_TOOL_PERMISSION"
                if [ "$RESOLVED_TOOL_PERMISSION" = "always-proceed" ]; then
                    EXTRA_ARGS+=(--dangerously-skip-permissions)
                fi
            fi
            if [ -n "$RESOLVED_ARTIFACT_POLICY" ]; then
                echo "   - artifactReviewPolicy: $RESOLVED_ARTIFACT_POLICY"
            fi

            SETTINGS_DIR="${PERSISTENT_DIR}/.gemini/antigravity-cli"
            SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
            mkdir -p "$SETTINGS_DIR"

            node -e '
            const fs = require("fs");
            const file = process.argv[1];
            const toolPermission = process.argv[2];
            const artifactPolicy = process.argv[3];
            let data = {};
            try {
                data = JSON.parse(fs.readFileSync(file, "utf8"));
            } catch (e) {}
            if (toolPermission) data.toolPermission = toolPermission;
            if (artifactPolicy) data.artifactReviewPolicy = artifactPolicy;
            fs.writeFileSync(file, JSON.stringify(data, null, 2));
            ' "$SETTINGS_FILE" "$RESOLVED_TOOL_PERMISSION" "$RESOLVED_ARTIFACT_POLICY" 2>/dev/null || true
        else
            echo "🛡️ Modo de permisos: Comportamiento por defecto de Antigravity (sin variables definidas)"
        fi

        exec agy --remote-control --hub-port "$HUB_PORT" --remote-control-name "$INSTANCE_NAME" "${EXTRA_ARGS[@]}" "$@"
        ;;

    *)
        # If user passed custom flags or commands
        exec "$@"
        ;;
esac
