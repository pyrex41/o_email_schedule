# Use OCaml Alpine base image
FROM ocaml/opam:debian-12-ocaml-5.1 as builder

# Install system dependencies
RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    libsqlite3-dev \
    libgmp-dev \
    libssl-dev \
    pkg-config \
    m4 \
    git \
    && sudo rm -rf /var/lib/apt/lists/*

# Set up opam environment
USER opam
WORKDIR /home/opam

# Copy opam files first for better caching
COPY --chown=opam:opam dune-project .
COPY --chown=opam:opam *.opam ./

# Install dependencies
RUN opam install --deps-only -y .

# Copy source code
COPY --chown=opam:opam . .

# Build the application
RUN eval $(opam env) && dune build --release

# Create production runtime image
FROM debian:bookworm-slim as runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgmp10 \
    sqlite3 \
    libsqlite3-0 \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fuse \
    wget \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Install TigrisFS (optimized FUSE driver for Tigris)
RUN wget -O /tmp/tigrisfs.deb https://github.com/tigrisdata/tigrisfs/releases/download/v1.2.1/tigrisfs_1.2.1_linux_amd64.deb && \
    dpkg -i /tmp/tigrisfs.deb && \
    rm /tmp/tigrisfs.deb

# Download and install sqlite3_rsync
RUN wget -O /usr/local/bin/sqlite3_rsync https://sqlite.org/src/raw/tool/sqlite3_rsync?name=sqlite3_rsync && \
    chmod +x /usr/local/bin/sqlite3_rsync

# Create app directory and mount points
WORKDIR /app
RUN mkdir -p /app/data /tigris

# Copy built executable
COPY --from=builder /home/opam/_build/default/bin/scheduler_cli.exe /app/scheduler_cli

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh

# Make executables
RUN chmod +x /app/scheduler_cli /app/entrypoint.sh

# Default command runs the entrypoint script
CMD ["/app/entrypoint.sh"] 