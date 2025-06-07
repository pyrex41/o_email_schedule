# Use OCaml Alpine base image
FROM ocaml/opam:alpine-5.1 as builder

# Install system dependencies
RUN sudo apk add --no-cache \
    sqlite-dev \
    libffi-dev \
    gmp-dev \
    openssl-dev \
    pkg-config \
    m4 \
    git

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

# Install runtime dependencies and Google Cloud SDK repository
RUN apt-get update && apt-get install -y \
    sqlite3 \
    libsqlite3-0 \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fuse \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK and gcsfuse
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && \
    apt-get install -y gcsfuse && \
    rm -rf /var/lib/apt/lists/*

# Download and install sqlite3_rsync
RUN wget -O /usr/local/bin/sqlite3_rsync https://sqlite.org/src/raw/tool/sqlite3_rsync?name=sqlite3_rsync && \
    chmod +x /usr/local/bin/sqlite3_rsync

# Create app directory and mount points
WORKDIR /app
RUN mkdir -p /app/data /gcs

# Copy built executable
COPY --from=builder /home/opam/_build/default/bin/scheduler_cli.exe /app/scheduler_cli

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh

# Make executables
RUN chmod +x /app/scheduler_cli /app/entrypoint.sh

# Default command runs the entrypoint script
CMD ["/app/entrypoint.sh"] 