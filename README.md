# Antigravity CLI Daemon para Coolify (con Railpack y PHP 8.4)

Este proyecto está configurado para desplegar el daemon de **Google Antigravity CLI (`agy`)** en modo **Remote Control** utilizando **Coolify** y su sistema de construcción **Railpack**.

Está preconfigurado para utilizar **PHP 8.4** (con **FrankenPHP / Caddy**) y contiene las herramientas necesarias (Composer, GitHub CLI `gh`, Node.js 24, Python 3) para desarrollar proyectos en la nube.

---

## 📋 Características

- 🤖 **Google Antigravity CLI (`agy`)**: Instalado automáticamente en el entorno y configurado para conectarse al panel de **Remote Control**.
- 🚀 **Despliegue con Railpack**: Configuración nativa `railpack.json` para despliegues instantáneos y sin Dockerfile en Coolify.
- 🐘 **PHP 8.4 + FrankenPHP (Caddy)**: Servidor de aplicaciones multihilo nativo con resolución dinámica de proyectos por subdominio en el puerto `8000`.
- 🧩 **Hook por Repositorio (`.agy-init.sh`)**: Soporte para scripts de inicialización personalizados dentro de cada proyecto clonado sin modificar el contenedor base.
- 🗄️ **MariaDB Integrado**: Servidor de BD interno configurado de manera automática en cada despliegue.
- 🐙 **GitHub CLI (`gh`)**: Incluido para operaciones de Git automatizadas o asistidas por el agente.
- 📦 **Node.js 24 (vía NVM)**: Instalado y persistido en el volumen de datos, listo para compilar assets frontend de Laravel (Vite, Tailwind, etc).
- 🐍 **Python 3 (`python3`, `pip`, `venv`)**: Preinstalado para scripts auxiliares, herramientas de análisis o automatizaciones del agente.

---

## 🌐 Servidor Web Dinámico (FrankenPHP / Caddy)

En lugar de ejecutar múltiples procesos `php artisan serve`, el contenedor levanta una única instancia de **FrankenPHP (Caddy)** en el puerto `8000` (`APP_PORT`) que resuelve dinámicamente el `DocumentRoot` según el subdominio:

- Petición a `https://sirio.tudominio.com` ➔ sirve `/app/workspace/sirio/public`
- Petición a `https://otro-repo.tudominio.com` ➔ sirve `/app/workspace/otro-repo/public`
- Acceso directo sin subdominio o por IP (`http://localhost:8000`) ➔ usa como *fallback* el primer repositorio clonado.
- Si el nombre del repositorio en GitHub contiene mayúsculas (ej. `Usuario/Sirio`), el `entrypoint.sh` crea automáticamente un enlace simbólico en minúsculas (`/app/workspace/sirio`) para que coincida siempre con el subdominio HTTP.

En **Coolify**, basta con apuntar tus subdominios (o un dominio comodín `*.tudominio.com`) al puerto `8000` del contenedor (por ejemplo: `https://sirio.tudominio.com:8000`).

---

## 🧩 Hook Opcional por Repositorio (`.agy-init.sh`)

Si un proyecto específico requiere tareas de aprovisionamiento adicionales (descargar bases de datos GeoIP, publicar assets especiales, crear enlaces simbólicos propios o inyectar configuraciones en `.env`), puedes incluir un archivo `.agy-init.sh` en la raíz de ese repositorio:

```bash
#!/bin/bash
# Ejemplo: /app/workspace/sirio/.agy-init.sh
echo "Configurando recursos específicos del proyecto..."
php artisan vendor:publish --tag=mis-assets --force
```

Durante el arranque, `entrypoint.sh` detectará y ejecutará automáticamente `.agy-init.sh` después de las migraciones y `storage:link`, pero **antes** de generar las cachés de Laravel (`config:cache`, `route:cache`, `view:cache`, `filament:optimize`), asegurando que cualquier ajuste quede incluido en la optimización final.

---

## 🗄️ Base de Datos Integrada (MariaDB)

Este entorno cuenta con un servidor de **MariaDB** instalado internamente, diseñado para facilitar el desarrollo y pruebas:
- Arranca automáticamente en el contenedor sin necesidad de servicios adicionales.
- Crea automáticamente la base de datos y usuario al iniciar el daemon tomando los valores de las variables de entorno `DB_DATABASE`, `DB_USERNAME`, y `DB_PASSWORD`.
- **Comportamiento por defecto:** Se ejecuta `php artisan migrate:fresh --seed` en cada inicio (`DB_FRESH_SEED=true`), ideal para entornos de desarrollo. Si deseas preservar datos y correr únicamente migraciones pendientes, establece `DB_FRESH_SEED=false`.

---

## 🚀 Cómo Desplegar en Coolify

### 1. Crear el Proyecto en Coolify
1. Ve a tu panel de **Coolify**.
2. Añade un nuevo recurso seleccionando **Public Repository** o **Private Repository** (donde tengas alojado este código).
3. Selecciona la opción de **Build Pack** y elige **Railpack** (si Coolify no lo auto-detecta).

### 2. Configurar Variables de Entorno y Persistencia
Antes de hacer el primer despliegue, configura lo siguiente en la pestaña de ajustes de Coolify:

**Variables de Entorno:**
- `INSTANCE_NAME`: Nombre descriptivo (ej. `mi-coolify-agy`).
- `APP_PORT`: (Opcional) Puerto donde escucha FrankenPHP/Caddy para servir tus proyectos web (por defecto `8000`).
- `GH_TOKEN`: (Opcional) Tu Personal Access Token (Classic) de GitHub. Puedes crearlo directamente con los permisos necesarios preseleccionados desde este enlace: **[👉 Crear Token de GitHub preconfigurado](https://github.com/settings/tokens/new?description=Antigravity+CLI+Daemon&scopes=repo,read:org,workflow)** (incluye `repo` para repositorios privados, `read:org` para organizaciones y `workflow` para flujos de CI/CD).
- `CLONE_REPOSITORIES`: Lista separada por comas de repositorios a clonar automáticamente (ej. `tu-usuario/repo1, https://github.com/tu-usuario/repo2.git`).
- `TARGET_BRANCH`: Rama a la que cambiar o crear al clonar (por defecto `antigravity`).
- `DB_DATABASE`: Nombre de la base de datos a crear (por defecto `laravel`).
- `DB_USERNAME`: Usuario de la base de datos (por defecto `laravel_user`).
- `DB_PASSWORD`: Contraseña del usuario (por defecto `secret`).
- `DB_FRESH_SEED`: (Opcional) Recrear BD y correr seeders (`migrate:fresh --seed`) en cada arranque (por defecto `true`). Define `false` para solo correr `migrate --force`.
- `AUTO_APPROVE`: (Opcional) Define `true` para auto-aprobar tanto herramientas como cambios de código sin confirmación interactiva.
- `TOOL_PERMISSION`: (Opcional) Control granular para herramientas y comandos de terminal (`"always-proceed"`, `"request-review"`, `"proceed-in-sandbox"`, `"strict"`).
- `ARTIFACT_REVIEW_POLICY`: (Opcional) Control granular para revisión de código y artefactos (`"always-proceed"`, `"asks-for-review"`, `"agent-decides"`). Si no se define ninguna, se mantiene el comportamiento por defecto de Antigravity.
- `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`, `GEOIP_DOWNLOAD_URL`, `GEOIP_DB_PATH`, `MAXMIND_ACCOUNT_ID`, `MAXMIND_LICENSE_KEY`: (Opcionales) Si se definen en Coolify, se inyectan automáticamente en el archivo `.env` de los proyectos clonados al inicializarse.

**Almacenamiento Persistente (Storage):**
Para que tu sesión de Google y el caché no se pierdan al redesplegar, añade un volumen persistente:
- **Source**: (Déjalo en blanco para que Coolify genere un volumen automático o pon un volumen nombrado).
- **Destination**: `/app/data`

### 3. Desplegar
Haz clic en **Deploy**. Railpack leerá el archivo `railpack.json`, instalará PHP 8.4 (con FrankenPHP/Caddy), MariaDB, Python 3, `gh` y el CLI de `agy`. Al iniciar el contenedor, configurará Node.js 24 (vía NVM en `/app/data/.nvm`), aprovisionará los repositorios y levantará tanto el servidor web como el daemon de Antigravity.

---

## 🔐 Autenticación Inicial (Paso Único)

La primera vez que el contenedor arranque, el daemon no podrá conectarse porque necesita autenticarse con tu cuenta de Google.

Tienes dos opciones:

#### Opción A: Autenticar desde la Terminal de Coolify (Recomendado)
1. En el panel de Coolify, entra a la pestaña **Terminal** de tu despliegue.
2. Ejecuta:
   ```bash
   bash ./entrypoint.sh login
   ```
3. Aparecerá una URL. Ábrela en tu navegador, inicia sesión con tu cuenta y autoriza la aplicación.
4. Una vez autorizado, el token se guardará en `/app/data/.gemini/`.
5. Reinicia el contenedor desde el panel de Coolify (botón Restart).

#### Opción B: Copiar tu sesión local
Si tienes `agy` en tu ordenador, puedes usar SFTP o subir el contenido de tu carpeta `~/.gemini/` local al directorio `/app/data/.gemini/` dentro del contenedor.

---

## 🛠️ Conexión al Remote Control

1. Abre tu navegador e ingresa a: **[https://antigravity.google](https://antigravity.google)**
2. En la sección **Remote Control**, verás tu instancia ejecutándose.
3. Puedes solicitar al agente que cree un proyecto en Laravel, ejecute comandos o analice el repositorio directamente en tu entorno de Coolify.
