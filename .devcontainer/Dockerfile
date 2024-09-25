FROM fedora:41

RUN sudo dnf clean all -y \
    && sudo dnf update -y \
    # && sudo dnf group install -y "C Development Tools and Libraries" "Development Tools" \
    && sudo dnf install -y zig \
    && sudo dnf install -y freetype freetype-devel expat expat-devel \
    && sudo dnf install -y mesa-libGL mesa-libGL-devel \
    && sudo dnf install -y wayland-devel libxkbcommon-devel wayland-protocols-devel extra-cmake-modules \
    && sudo dnf install -y gtk4-devel gcc libadwaita-devel \
    && sudo dnf install -y bat eza fish fzf just ripgrep unzip util-linux-user

RUN cd /tmp \
    && curl -L https://github.com/zigtools/zls/releases/download/0.13.0/zls-aarch64-linux.tar.xz | tar xJ \
    && mv zls /usr/local/bin

RUN groupadd -g 1000 dev \
    && useradd -m -u 1000 -g dev dev -s /usr/bin/fish \
    && echo "dev ALL=(root) NOPASSWD: ALL" > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    && chown -R dev:dev /home/dev 

USER dev
