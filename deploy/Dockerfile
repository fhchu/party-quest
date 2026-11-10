# The production image: the relay, the game server (Godot running the
# project from source, so no export templates are needed) and the web export.
# deploy/deploy.sh (on the Mac) and .github/workflows/release.yml build it
# for linux/amd64, after deploy/export-web.sh has filled deploy/web.

# The relay is cross-compiled natively; only the final stage is emulated.
FROM --platform=$BUILDPLATFORM golang:1.26 AS relay
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY relay/go.mod relay/go.sum ./
RUN go mod download
COPY relay/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /relay .

FROM debian:bookworm-slim
# Must match the editor's version (game/README.md).
ARG GODOT_VERSION=4.7.2
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip /tmp/godot.zip -d /tmp \
	&& mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& rm /tmp/godot.zip \
	&& apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home game && mkdir -p /data/acme && chown game /data/acme
COPY --from=relay /relay /usr/local/bin/relay
COPY deploy/entrypoint.sh /usr/local/bin/entrypoint
COPY --chown=game deploy/web/ /app/web/
COPY --chown=game game/ /app/game/
USER game
RUN godot --headless --path /app/game --import

# entrypoint.sh's ports; compose.yaml maps 443 and 80 to them.
EXPOSE 8443/udp 8443/tcp 8080/tcp
ENTRYPOINT ["entrypoint"]
