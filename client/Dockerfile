# Headless game server: runs the project from source with a stock Godot
# binary, so no export templates are needed. Browsers reach it through the
# relay (relay/Dockerfile); keep port 9081 private to that network.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip /tmp/godot.zip -d /tmp \
	&& mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& rm /tmp/godot.zip \
	&& apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /game
COPY . .
RUN godot --headless --import

EXPOSE 9081
CMD ["godot", "--headless", "--path", "/game", "--", "--server", "--bind=0.0.0.0"]
