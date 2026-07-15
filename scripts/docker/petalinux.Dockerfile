# ---------------------------------------------------------------------------
# zynq_toolbox PetaLinux runner
#
# OS-level environment PetaLinux builds need. Does NOT contain PetaLinux
# itself -- that's installed once into the `petalinux-tools` volume
# (see scripts/docker/install-petalinux.sh), then mounted read-only here at runtime.
# This image needs network access UNLESS you're using the offline
# downloads/sstate-cache volumes -- see docker_install.md.
# ---------------------------------------------------------------------------

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_UID=1000
ARG BUILD_GID=1000

# PetaLinux requires /bin/sh -> bash, not dash.
RUN ln -sf /bin/bash /bin/sh

# This image also doubles as the install-time container for the AMD/Xilinx
# unified installer (see install-petalinux.sh) -- no separate throwaway
# image for that anymore. libxext6 through lsb-release below are packages
# the installer's GUI front-end needs on top of what a PetaLinux build
# already required; not needed for headless petalinux-build runs, but
# keeping one image covers both without a second package list to keep in
# sync.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    xterm \
    autoconf \
    libtool \
    texinfo \
    zlib1g-dev \
    gcc-multilib \
    build-essential \
    libncurses5-dev \
    libtinfo5 \
    git \
    make \
    sudo \
    ca-certificates \
    locales \
    chrpath \
    socat \
    tofrodos \
    iproute2 \
    unzip \
    tar \
    diffstat \
    cpio \
    rsync \
    file \
    gawk \
    device-tree-compiler \
    python3 \
    python3-pip \
    libpython3-dev \
    wget \
    curl \
    libxext6 \
    libxtst6 \
    libxi6 \
    libxrender1 \
    libsm6 \
    libice6 \
    fontconfig \
    libfreetype6 \
    xz-utils \
    less \
    bc \
    lsb-release \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Non-root build user -- PetaLinux refuses to run as root.
RUN groupadd -g ${BUILD_GID} builder \
    && useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /workspace

COPY --chown=builder:builder entrypoint-petalinux.sh /home/builder/entrypoint.sh
RUN chmod +x /home/builder/entrypoint.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]
