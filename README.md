# Antigravity CLI Daemon para Coolify (con Railpack y PHP 8.4)

Este proyecto está configurado para desplegar el daemon de **Google Antigravity CLI (`agy`)** en modo **Remote Control** utilizando **Coolify** y su sistema de construcción **Railpack**.

Está preconfigurado para utilizar **PHP 8.4** y contiene las herramientas necesarias (Composer, GitHub CLI `gh`, Node.js) para desarrollar proyectos en la nube.

---

## 📋 Características

- 🤖 **Google Antigravity CLI (`agy`)**: Instalado automáticamente en el entorno y configurado para conectarse al panel de **Remote Control**.
- 🚀 **Despliegue con Railpack**: Configuración nativa `railpack.json` para despliegues instantáneos y sin Dockerfile en Coolify.
- 🐘 **PHP 8.4**: Versión forzada mediante `composer.json` y `railpack.json`.
- 🗄️ **MariaDB Integrado**: Servidor de BD interno configurado de manera automática en cada despliegue.
- 🐙 **GitHub CLI (`gh`)**: Incluido para operaciones de Git automatizadas o asistidas por el agente.
- 📦 **Node.js 20**: Listo para compilar assets frontend de Laravel (Vite, Tailwind, etc).

---

## 🗄️ Base de Datos Integrada (MariaDB)

Este entorno cuenta con un servidor de **MariaDB** instalado internamente, diseñado para facilitar el desarrollo y pruebas:
- Arranca automáticamente en el contenedor sin necesidad de servicios adicionales.
- Crea automáticamente la base de datos y usuario al iniciar el daemon tomando los valores de las variables de entorno `DB_DATABASE`, `DB_USERNAME`, y `DB_PASSWORD`.
- **Importante:** La base de datos es efímera, por lo que **se vaciará en cada despliegue**. Esto es ideal para flujos de trabajo donde se ejecuten comandos como `php artisan migrate --seed` en cada iteración del despliegue.

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
- `GH_TOKEN`: (Opcional) Tu Personal Access Token de GitHub.
- `DB_DATABASE`: Nombre de la base de datos a crear (por defecto `laravel`).
- `DB_USERNAME`: Usuario de la base de datos (por defecto `laravel_user`).
- `DB_PASSWORD`: Contraseña del usuario (por defecto `secret`).

**Almacenamiento Persistente (Storage):**
Para que tu sesión de Google y el caché no se pierdan al redesplegar, añade un volumen persistente:
- **Source**: (Déjalo en blanco para que Coolify genere un volumen automático o pon un volumen nombrado).
- **Destination**: `/app/data`

### 3. Desplegar
Haz clic en **Deploy**. Railpack leerá el archivo `railpack.json`, instalará PHP 8.4, Node 20, y descargará los binarios de `agy` y `gh`. Al finalizar, el contenedor arrancará con el daemon de Antigravity.

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
