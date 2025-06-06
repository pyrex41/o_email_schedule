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

# Create minimal runtime image
FROM alpine:3.18 as runtime

# Install runtime dependencies
RUN apk add --no-cache \
    sqlite \
    libffi \
    gmp \
    openssl \
    ca-certificates

# Create app directory
WORKDIR /app

# Copy built executable
COPY --from=builder /home/opam/_build/default/bin/scheduler_cli.exe /app/scheduler_cli

# Make executable
RUN chmod +x /app/scheduler_cli

# Create data directory for volume mount
RUN mkdir -p /app/data

# Default command (can be overridden)
CMD ["/app/scheduler_cli", "/app/data/contacts.sqlite3"] 