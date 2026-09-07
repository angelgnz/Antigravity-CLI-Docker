# Antigravity CLI Daemon en Docker (VPS) con PHP, Laravel y GitHub CLI

Este proyecto proporciona un entorno Dockerizado optimizado y listo para producción para ejecutar el daemon de **Google Antigravity CLI (`agy`)** en modo **Remote Control** en un VPS.

Incluye soporte nativo para desarrollo con **PHP 8.3**, **Composer**, **Laravel**, **Node.js 20 LTS** y **GitHub CLI (`gh`)**, con persistencia completa de sesiones, tokens de autenticación y bases de datos.

---

## 📋 Características

- 🤖 **Google Antigravity CLI (`agy`)**: Instalado y configurado para correr como daemon en segundo plano y conectarse al panel de **Remote Control** en [antigravity.google](https://antigravity.google).
- 🐘 **PHP 8.3 & Laravel**: Con todas las extensiones requeridas (`curl`, `mbstring`, `xml`, `zip`, `mysql`, `pgsql`, `sqlite3`, `intl`, `bcmath`, `gd`, `soap`), Composer y el instalador oficial de Laravel.
- 🐙 **GitHub CLI (`gh`)**: Soporte para autenticación no interactiva mediante token (`GH_TOKEN`) o interactiva (`gh auth login`), con persistencia de credenciales.
- 📦 **Node.js 20 LTS & npm**: Para compilar frontend de Laravel con Vite o Tailwind CSS.
- 🗄️ **Base de datos opcional**: Servicio MariaDB/MySQL preconfigurado mediante perfiles de Docker Compose (`--profile with-db`).
- 🔒 **Seguridad**: Ejecución con usuario no-root (`antigravity`), con acceso `sudo` sin contraseña para permitir al agente instalar dependencias cuando lo necesite.
- 💾 **Persistencia Total**: Volúmenes de Docker para tokens OAuth de Antigravity, configuración de GitHub, caché de Composer y el código de `/workspace`.

---

## 🚀 Despliegue Paso a Paso en tu VPS

### 1. Clonar o copiar el proyecto a tu VPS

Copia esta carpeta a tu VPS (por ejemplo en `~/antigravity-docker`):

```bash
cd ~/antigravity-docker
```

### 2. Configurar el archivo de entorno

Copia la plantilla `.env.example` a `.env`:

```bash
cp .env.example .env
```

Edita `.env` con tus preferencias:

```bash
nano .env
```

Parámetros clave:
- `INSTANCE_NAME`: Nombre descriptivo con el que aparecerá este VPS en tu panel de Remote Control (ej. `vps-produccion`, `vps-laravel`).
- `GH_TOKEN`: (Opcional) Tu Personal Access Token de GitHub para clonar y gestionar repositorios sin interactuar.
- `DB_*`: Credenciales de la base de datos si utilizas MySQL/MariaDB para Laravel.

---

### 3. Autenticación Inicial de Antigravity (Paso Único)

El daemon requiere autenticar tu cuenta de Google la primera vez antes de ejecutarse en modo desatendido. Tienes **dos opciones**:

#### Opción A: Autenticar directamente en el VPS (Recomendada)
Ejecuta el asistente interactivo de login:

```bash
docker compose run --rm antigravity-daemon login
```

1. Verás un enlace de autenticación de Google en la terminal.
2. Abre el enlace en tu navegador web e inicia sesión con tu cuenta autorizada de Antigravity.
3. El token se guardará automáticamente en el volumen persistente de Docker.
4. Presiona `Ctrl + C` una vez autenticado para salir.

#### Opción B: Copiar credenciales desde tu computadora local
Si ya usas Antigravity CLI en tu PC local, puedes copiar tu sesión existente al VPS:
```bash
# En tu PC local (reemplaza usuario y tu-vps-ip):
scp -r ~/.gemini/ usuario@tu-vps-ip:~/antigravity-docker/gemini-backup/
```
Y luego copiar los archivos dentro del volumen de Docker.

---

### 4. Iniciar el Daemon en Segundo Plano

Una vez autenticado, inicia el contenedor:

```bash
# Solo el agente Antigravity (usando SQLite o base de datos externa):
docker compose up -d

# O si deseas iniciar también el contenedor de MariaDB/MySQL local:
docker compose --profile with-db up -d
```

Verifica que el daemon esté funcionando y revisa los logs:

```bash
docker compose logs -f antigravity-daemon
```

Verás una salida confirmando que el daemon se ha conectado exitosamente al servicio de Remote Control.

---

### 5. Acceder por Control Remoto

1. Abre tu navegador e ingresa a: **[https://antigravity.google](https://antigravity.google)**
2. Inicia sesión con la misma cuenta de Google utilizada en el paso de autenticación.
3. En la sección **Remote Control** / **Instancias**, verás aparecer tu VPS con el nombre configurado en `INSTANCE_NAME`.
4. ¡Listo! Puedes enviar instrucciones, crear tareas, revisar código y ejecutar proyectos de Laravel directamente en tu VPS desde el navegador o la aplicación Antigravity.

---

## 🛠️ Comandos Útiles y Flujo de Trabajo

### Estado del Daemon
Para consultar el estado del daemon:
```bash
docker compose exec antigravity-daemon agy remote-control status
```

### Abrir una terminal interactiva dentro del contenedor
Si deseas entrar a la terminal del contenedor para verificar archivos o herramientas:
```bash
docker compose exec -it antigravity-daemon bash
```

### Trabajar con GitHub CLI (`gh`)
- Si definiste `GH_TOKEN` en `.env`, `gh` ya estará listo para usarse.
- Para verificar el estado de GitHub:
  ```bash
  docker compose exec antigravity-daemon gh auth status
  ```
- Para clonar un repositorio privado en `/workspace`:
  ```bash
  docker compose exec antigravity-daemon gh repo clone mi-usuario/mi-proyecto /workspace/mi-proyecto
  ```

### Trabajar con Laravel y Composer
- **Crear un nuevo proyecto Laravel**:
  ```bash
  docker compose exec antigravity-daemon composer create-project laravel/laravel mi-app
  ```
- **Ejecutar migraciones**:
  ```bash
  docker compose exec -w /workspace/mi-app antigravity-daemon php artisan migrate
  ```
- **Iniciar servidor de desarrollo Laravel**:
  ```bash
  docker compose exec -w /workspace/mi-app antigravity-daemon php artisan serve --host 0.0.0.0 --port 8000
  ```
  *(Podrás acceder a la aplicación en `http://tu-vps-ip:8000`)*

### Reiniciar o Detener
- **Reiniciar el daemon**:
  ```bash
  docker compose restart antigravity-daemon
  ```
- **Detener el servicio**:
  ```bash
  docker compose down
  ```
- **Actualizar la imagen o recompilar**:
  ```bash
  docker compose build --no-cache
  docker compose up -d
  ```

---

## 📂 Estructura de Volúmenes Persistentes

Los datos persistentes se almacenan en volúmenes gestionados por Docker:

| Volumen | Ubicación en el contenedor | Propósito |
|---|---|---|
| `./workspace` | `/workspace` | Código de tus proyectos Laravel y archivos |
| `antigravity_gemini_data` | `/home/antigravity/.gemini` | Token OAuth y sesión de Google Antigravity |
| `antigravity_state_data` | `/home/antigravity/.antigravity` | Memoria del agente, logs e historial |
| `antigravity_gh_config` | `/home/antigravity/.config/gh` | Configuración y credenciales de GitHub CLI |
| `antigravity_composer_cache`| `/home/antigravity/.composer` | Caché de descargas de Composer |
| `antigravity_db_data` | `/var/lib/mysql` | Datos persistentes de la base de datos MariaDB |

---

## ❓ Preguntas Frecuentes y Solución de Problemas

### ¿Qué puertos debo abrir en el firewall del VPS?
- Para el **Remote Control de Antigravity no necesitas abrir ningún puerto entrante** en el firewall de tu VPS, ya que el daemon se conecta mediante túneles salientes seguros hacia la infraestructura de Google.
- Solo necesitas abrir el puerto `8000` (o el que configures en `APP_PORT`) si deseas ver tu aplicación Laravel desde tu navegador personal en `http://tu-vps-ip:8000`.

### El daemon dice que falta autenticación
Ejecuta en tu VPS:
```bash
docker compose run --rm antigravity-daemon login
```
Abre la URL indicada, aprueba el acceso con tu cuenta de Google y cuando finalice el proceso, reinicia con `docker compose up -d`.
