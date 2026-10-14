FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships a default "ubuntu" user with UID/GID 1000.
# Remove it so our own user can take UID 1000.
RUN userdel -r ubuntu 2>/dev/null || true

# SSH server + dev tools (Python, Go, Node.js, git ...)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server sudo ca-certificates \
        python3 python3-pip python3-venv \
        golang-go nodejs npm \
        git curl wget nano tmux htop unzip \
        build-essential iproute2 iputils-ping \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    # Host keys are generated at runtime (and persisted), never baked into the image
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd \
    && chmod 755 /run/sshd

# Hardening (sshd uses first-match-wins; sshd_config.d is included at the top)
COPY sshd_hardening.conf /etc/ssh/sshd_config.d/10-hardening.conf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

CMD ["/usr/local/bin/entrypoint.sh"]
