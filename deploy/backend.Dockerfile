# The backend's image: one static Go program, no shell. Docker's health
# check runs the program itself with -healthcheck (deploy/compose.yaml).
# deploy/deploy.sh (on the Mac) and .github/workflows/release.yml build it
# for linux/amd64.

# Cross-compiled natively, like the relay in deploy/Dockerfile. Must match
# the toolchain in server/go.mod and the relay stage there.
FROM --platform=$BUILDPLATFORM golang:1.27.4 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/usr/local/bin/api ./cmd/api \
	&& mkdir -p /out/data /out/tmp

FROM gcr.io/distroless/static-debian12:nonroot
# /data holds the databases (a volume, which takes this ownership when it is
# first made); /tmp holds the start marker, which must not outlive the
# container.
COPY --from=build --chown=nonroot:nonroot /out/ /
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/api"]
