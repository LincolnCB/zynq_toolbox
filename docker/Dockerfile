# ---------------------------------------------------------------------------
# zynq_toolbox unified build image
#
# One image, three jobs (selected at `docker run` time via ZYNQ_MODE, see
# entrypoint.sh):
#
#   ZYNQ_MODE=tools    Runs the AMD/Xilinx unified installer, builds
#                      cocotb/Verilator -- all written into the `zynq-tools`
#                      volume. One-time (or once-per-version) setup step.
#   ZYNQ_MODE=offline  Extracts the PetaLinux sstate-cache/downloads tarballs
#                      into the `zynq-petalinux-offline` volume. Optional,
#                      one-time setup step.
#   ZYNQ_MODE=dev      (default) The actual build environment -- mounts the
#                      repo and both volumes, sets up env vars, drops you
#                      into a shell.
#
# Every package this image could possibly need for any of the three jobs is
# baked in up front, so none of the three modes need their own `apt-get` at
# `docker run` time (the old install-xilinx-tools.sh ran one in a throwaway
# ubuntu:20.04 container -- that's gone now, it's all here instead).
# ---------------------------------------------------------------------------

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
# Match to your host user so files written into bind-mounted volumes (the
# repo, build outputs) aren't owned by a random UID. Pass at build time
# with --build-arg BUILD_UID=$(id -u) --build-arg BUILD_GID=$(id -g)
ARG BUILD_UID=1000
ARG BUILD_GID=1000

# PetaLinux requires /bin/sh -> bash, not dash (Ubuntu's default).
RUN ln -sf /bin/bash /bin/sh

RUN apt-get update && apt-get install -y --no-install-recommends \
    # --- PetaLinux / general build workflow ---------------------------
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
    xz-utils \
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
    less \
    bc \
    lsb-release \
    # --- AMD/Xilinx unified installer GUI (X11) ------------------------
    libxext6 \
    libxtst6 \
    libxi6 \
    libxrender1 \
    libsm6 \
    libice6 \
    fontconfig \
    libfreetype6 \
    # --- Verilator build prerequisites ---------------------------------
    help2man \
    perl \
    perl-doc \
    flex \
    bison \
    ccache \
    libgoogle-perftools-dev \
    numactl \
    libfl2 \
    libfl-dev \
    zlibc \
    && rm -rf /var/lib/apt/lists/*

# The unified installer expects a `python` binary on PATH.
RUN ln -sf /usr/bin/python3 /usr/bin/python

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Non-root build user -- PetaLinux refuses to run as root. `tools`/`offline`
# mode still run as root (see docker-compose.yml), since they write into
# fresh volumes that start out root-owned; both chmod their output to be
# world-readable/executable afterward so this user can use it in `dev` mode.
RUN groupadd -g ${BUILD_GID} builder \
    && useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup-tools.sh /usr/local/bin/setup-tools.sh
COPY setup-offline.sh /usr/local/bin/setup-offline.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-tools.sh /usr/local/bin/setup-offline.sh

USER builder
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]