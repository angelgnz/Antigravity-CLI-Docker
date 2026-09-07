# ==============================================================================
# Antigravity CLI Remote-Control Daemon + PHP 8.3 / Laravel + GitHub CLI
# ==============================================================================
FROM ubuntu:24.04

LABEL maintainer="Antigravity Team" \
      description="Docker container to run Antigravity CLI daemon for Remote Control on a VPS with PHP, Laravel, Node.js, and GitHub CLI"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 1. Install base utilities and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    git \
    jq \
    tmux \
    sudo \
    build-essential \
    unzip \
    zip \
    nano \
    procps \
    openssh-client \
    sqlite3 \
    libsqlite3-dev \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# 2. Install GitHub CLI (gh)
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# 3. Install PHP 8.3 and essential Laravel extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    php8.3-cli \
    php8.3-common \
    php8.3-curl \
    php8.3-mbstring \
    php8.3-xml \
    php8.3-zip \
    php8.3-mysql \
    php8.3-pgsql \
    php8.3-sqlite3 \
    php8.3-intl \
    php8.3-bcmath \
    php8.3-gd \
    php8.3-soap \
    && rm -rf /var/lib/apt/lists/*

# 4. Install Composer (Official binary from composer image)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# 5. Install Node.js 20 LTS & npm (Required for modern Laravel frontends: Vite, Tailwind, etc.)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# 6. Install Google Antigravity CLI (agy)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin && \
    chmod +x /usr/local/bin/agy

# 7. Create non-root developer user with passwordless sudo
ARG USERNAME=antigravity
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# 8. Setup directories and permissions
RUN mkdir -p /workspace \
             /home/${USERNAME}/.gemini \
             /home/${USERNAME}/.antigravity \
             /home/${USERNAME}/.config/gh \
             /home/${USERNAME}/.composer && \
    chown -R ${USERNAME}:${USERNAME} /workspace \
                                     /home/${USERNAME}/.gemini \
                                     /home/${USERNAME}/.antigravity \
                                     /home/${USERNAME}/.config \
                                     /home/${USERNAME}/.composer

# 9. Configure entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Environment settings for non-root user
USER ${USERNAME}
WORKDIR /workspace

# Include composer global vendor bin and local user bin in PATH
ENV PATH="/home/${USERNAME}/.composer/vendor/bin:/home/${USERNAME}/.local/bin:${PATH}"

# Install Laravel Installer globally via Composer
RUN composer global require laravel/installer --quiet --no-interaction

EXPOSE 4400 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]
