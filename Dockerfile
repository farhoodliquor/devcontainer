FROM jlesage/baseimage-gui:ubuntu-22.04-v4

# Bust cache for all layers below (base image pull is still cached)
ARG CACHE_BUST

# Set environment variables
ENV APP_NAME="Dev Container" \
    KEEP_APP_RUNNING=1 \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    SECURE_CONNECTION=1 \
    USER_ID=1000 \
    GROUP_ID=1000 \
    CLAUDE_USER=user

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    ca-certificates \
    git \
    build-essential \
    python3 \
    python3-pip \
    jq \
    unzip \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Chrome and xdg-utils (needed for xdg-open to work in VNC)
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    apt-get install -y google-chrome-stable xdg-utils && \
    rm -rf /var/lib/apt/lists/*

# Chrome wrapper: adds flags required for running inside a Docker container.
# xdg-open (used by Claude Code on Linux) respects $BROWSER, so pointing it
# here ensures the OAuth popup works without manual --no-sandbox invocations.
# Cleans up crash lock files and suppresses the crash-restore bubble so that
# sessions/cookies survive unclean pod shutdowns (SIGKILL).
RUN printf '#!/bin/bash\n\
CHROME_DIR="/config/userdata/.config/google-chrome"\n\
mkdir -p "$CHROME_DIR"\n\
# Remove stale lock files left by unclean container shutdown\n\
rm -f "$CHROME_DIR/SingletonLock" "$CHROME_DIR/SingletonSocket" "$CHROME_DIR/SingletonCookie"\n\
# Mark the previous session as clean so Chrome does not clear cookies\n\
PREFS="$CHROME_DIR/Default/Preferences"\n\
if [ -f "$PREFS" ]; then\n\
  sed -i '\''s/"exit_type":"Crashed"/"exit_type":"Normal"/g; s/"exited_cleanly":false/"exited_cleanly":true/g'\'' "$PREFS"\n\
fi\n\
exec /usr/bin/google-chrome-stable \\\n\
  --no-sandbox \\\n\
  --disable-dev-shm-usage \\\n\
  --disable-gpu \\\n\
  --disable-session-crashed-bubble \\\n\
  --user-data-dir="$CHROME_DIR" \\\n\
  "$@"\n' > /usr/local/bin/google-chrome && \
    chmod +x /usr/local/bin/google-chrome

# Install Node.js LTS via NodeSource
ARG NODE_MAJOR=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# Install Claude Code native binary (npm wrapper breaks remote control)
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    cp /root/.local/bin/claude /usr/local/bin/claude && \
    rm -rf /root/.local/bin/claude && \
    claude --version

# Disable Claude Code auto-updater (doesn't work inside Docker)
RUN mkdir -p /etc/skel/.claude && \
    echo '{"env":{"DISABLE_AUTOUPDATER":"1"}}' > /etc/skel/.claude/settings.json

# Install OpenCode AI coding agent
RUN OPENCODE_VERSION=$(curl -sL https://api.github.com/repos/opencode-ai/opencode/releases/latest | jq -r '.tag_name') && \
    curl -fsSL "https://github.com/opencode-ai/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x86_64.tar.gz" | \
    tar -xz -C /usr/local/bin opencode && \
    chmod +x /usr/local/bin/opencode

# Install Crush AI coding agent (OpenCode successor by Charm)
RUN CRUSH_VERSION=$(curl -sL https://api.github.com/repos/charmbracelet/crush/releases/latest | jq -r '.tag_name' | sed 's/^v//') && \
    curl -fsSL "https://github.com/charmbracelet/crush/releases/download/v${CRUSH_VERSION}/crush_${CRUSH_VERSION}_Linux_x86_64.tar.gz" -o /tmp/crush.tar.gz && \
    tar -xzf /tmp/crush.tar.gz -C /tmp && \
    mv /tmp/crush_${CRUSH_VERSION}_Linux_x86_64/crush /usr/local/bin/crush && \
    chmod +x /usr/local/bin/crush && \
    rm -rf /tmp/crush*

# Install Helm CLI for Kubernetes chart management
ARG HELM_VERSION=4.1.3
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | \
    tar -xz --strip-components=1 -C /usr/local/bin linux-amd64/helm && \
    chmod +x /usr/local/bin/helm

# Install OpenTofu (open-source Terraform alternative)
ARG OPENTOFU_VERSION=1.11.5
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_amd64.zip" -o /tmp/tofu.zip && \
    unzip -o /tmp/tofu.zip -d /usr/local/bin tofu && \
    chmod +x /usr/local/bin/tofu && \
    rm /tmp/tofu.zip

# Install GitHub CLI (gh) via official APT repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install kubeseal CLI for Bitnami Sealed Secrets
RUN KUBESEAL_VERSION=$(curl -sL https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | jq -r '.tag_name' | sed 's/^v//') && \
    curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" | \
    tar -xz -C /usr/local/bin kubeseal && \
    chmod +x /usr/local/bin/kubeseal

# Install kubectl CLI for Kubernetes cluster management
RUN KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt) && \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Install k9s terminal UI for Kubernetes
RUN K9S_VERSION=$(curl -sL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name') && \
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" | \
    tar -xz -C /usr/local/bin k9s && \
    chmod +x /usr/local/bin/k9s

# Install Flux CLI for GitOps operations
RUN FLUX_VERSION=$(curl -sL https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r '.tag_name' | sed 's/^v//') && \
    curl -fsSL "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" | \
    tar -xz -C /usr/local/bin flux && \
    chmod +x /usr/local/bin/flux

# ── LSP servers for Claude Code language intelligence ──

# npm-based LSP servers: Python (pyright), TypeScript/JavaScript, PHP
RUN npm install -g pyright typescript-language-server typescript intelephense

# Install Go runtime and gopls LSP server
ARG GO_VERSION=1.26.1
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local && \
    /usr/local/go/bin/go install golang.org/x/tools/gopls@latest && \
    mv /root/go/bin/gopls /usr/local/bin/gopls && \
    rm -rf /root/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Install clangd LSP server (C/C++)
RUN apt-get update && \
    apt-get install -y clangd && \
    rm -rf /var/lib/apt/lists/*

# Install rust-analyzer LSP server (Rust) — standalone binary, no full toolchain needed
RUN RUST_ANALYZER_VERSION=$(curl -sL https://api.github.com/repos/rust-lang/rust-analyzer/releases/latest | jq -r '.tag_name') && \
    curl -fsSL "https://github.com/rust-lang/rust-analyzer/releases/download/${RUST_ANALYZER_VERSION}/rust-analyzer-x86_64-unknown-linux-gnu.gz" | \
    gunzip > /usr/local/bin/rust-analyzer && \
    chmod +x /usr/local/bin/rust-analyzer

# Install lua-language-server (Lua)
RUN LUA_LS_VERSION=$(curl -sL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest | jq -r '.tag_name') && \
    mkdir -p /opt/lua-language-server && \
    curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-linux-x64.tar.gz" | \
    tar -xz -C /opt/lua-language-server && \
    ln -s /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server

# Install JDK for Java/Kotlin LSP servers
RUN apt-get update && \
    apt-get install -y openjdk-17-jdk-headless && \
    rm -rf /var/lib/apt/lists/*

# Install kotlin-language-server
RUN KLS_VERSION=$(curl -sL https://api.github.com/repos/fwcd/kotlin-language-server/releases/latest | jq -r '.tag_name') && \
    curl -fsSL "https://github.com/fwcd/kotlin-language-server/releases/download/${KLS_VERSION}/server.zip" -o /tmp/kls.zip && \
    unzip -o /tmp/kls.zip -d /opt/kotlin-language-server && \
    ln -s /opt/kotlin-language-server/server/bin/kotlin-language-server /usr/local/bin/kotlin-language-server && \
    rm /tmp/kls.zip

# Install jdtls (Java LSP) — Eclipse JDT Language Server
RUN JDTLS_TARBALL=$(curl -sL https://download.eclipse.org/jdtls/snapshots/latest.txt) && \
    mkdir -p /opt/jdtls && \
    curl -fsSL "https://download.eclipse.org/jdtls/snapshots/${JDTLS_TARBALL}" | tar -xz -C /opt/jdtls && \
    printf '#!/bin/bash\nexec java -Declipse.application=org.eclipse.jdt.ls.core.id1 -Dosgi.bundles.defaultStartLevel=4 -Declipse.product=org.eclipse.jdt.ls.core.product -jar /opt/jdtls/plugins/org.eclipse.equinox.launcher_*.jar -configuration /opt/jdtls/config_linux "$@"\n' > /usr/local/bin/jdtls && \
    chmod +x /usr/local/bin/jdtls

# Install VSCode (using Microsoft's current recommended setup)
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg && \
    install -D -o root -g root -m 644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg && \
    rm -f /tmp/microsoft.gpg && \
    printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/microsoft.gpg\n' \
      > /etc/apt/sources.list.d/vscode.sources && \
    apt-get update && \
    apt-get install -y code && \
    rm -rf /var/lib/apt/lists/*

# Install Google Antigravity IDE
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
      gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
      > /etc/apt/sources.list.d/antigravity.list && \
    # Clear package cache to force fresh repository data
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    # Show available versions for debugging
    apt-cache policy antigravity && \
    # Install latest version
    apt-get install -y --no-install-recommends antigravity && \
    # Display installed version
    dpkg -l | grep antigravity && \
    rm -rf /var/lib/apt/lists/*

# Pre-configure Antigravity to skip onboarding/setup on first run
RUN mkdir -p /etc/skel/.config/antigravity/User/globalStorage && \
    echo '{"antigravityUnifiedStateSync.seenNuxOneTimeMigration": true, "antigravityUnifiedStateSync.browserOnboarding.completed": true, "antigravityUnifiedStateSync.hasOnboardingCompleted": true, "browserOnboarding.hasSeenWelcome": true, "antigravityUnifiedStateSync.browserPreferences.hasAddedLocalhostToAllowlist": true, "antigravityUnifiedStateSync.oauthToken.hasLegacyMigrated": true, "antigravityUnifiedStateSync.auth.tokenSyncEnabled": true, "antigravityUnifiedStateSync.auth.cloudSyncEnabled": true, "theme": "vs-dark"}' \
      > /etc/skel/.config/antigravity/User/globalStorage/storage.json && \
    echo '{"workbench.startupEditor": "none", "workbench.welcomePage.walkthroughs.openOnInstall": false, "workbench.tips.enabled": false, "extensions.ignoreRecommendations": true, "telemetry.telemetryLevel": "off", "update.mode": "none", "extensions.autoUpdate": false, "extensions.autoCheckUpdates": false, "workbench.enableExperiments": true, "workbench.settings.enableNaturalLanguageSearch": true, "antigravity.onboarding.completed": true, "antigravity.browserOnboarding.completed": true, "antigravity.setup.completed": true, "antigravity.ai.enabled": true, "antigravity.ai.autoComplete.enabled": true, "antigravity.ai.chat.enabled": true, "antigravity.ai.codeActions.enabled": true, "antigravity.ai.explainCode.enabled": true, "antigravity.ai.generateCode.enabled": true, "antigravity.ai.optimizeCode.enabled": true, "antigravity.ai.autoSuggest.enabled": true, "antigravity.telemetry.crashReporter": "on", "antigravity.ai.acceptTerms": true, "antigravity.auth.syncState": true, "antigravity.auth.enableTokenSync": true, "antigravity.ai.enableCloudSync": true, "antigravity.settings.sync": true}' \
      > /etc/skel/.config/antigravity/User/settings.json && \
    # Validate Antigravity installation
    /usr/share/antigravity/antigravity --version || echo "WARNING: Antigravity version check failed"

# Install OpenSSH server (for SSH IDE mode)
RUN apt-get update && \
    apt-get install -y openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# Create user user with specific UID/GID
RUN groupadd -g 1000 user && \
    useradd -u 1000 -g 1000 -m -s /bin/bash user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create workspace directory
RUN mkdir -p /workspace && \
    chown -R user:user /workspace

# Copy startup scripts
COPY --chmod=755 scripts/startapp.sh /startapp.sh
COPY --chmod=755 scripts/init-repo.sh /usr/local/bin/init-repo
# Fix app user shell after baseimage-gui creates it at runtime
COPY --chmod=755 scripts/cont-init-user.sh /etc/cont-init.d/20-fix-user-shell.sh
COPY --chmod=755 scripts/cont-init-sshd.sh /etc/cont-init.d/25-start-sshd.sh

# Set working directory
WORKDIR /workspace

# Configure container to run as user user
ENV HOME=/config/userdata \
    USER=user \
    BROWSER=/usr/local/bin/google-chrome

# Expose VNC port (baseimage-gui default)
EXPOSE 5800

# Set app name for baseimage-gui
RUN set-cont-env APP_NAME "Dev Container"
