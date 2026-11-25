# The backend's image: one static Go program, no shell. Docker's health
# check runs the program itself with -healthcheck (deploy/compose.yaml).
# deploy/deploy.sh (on the Mac) and .github/workflows/release.yml build it
# for linux/amd64.

# From deploy/build.env, as a build arg.
ARG GO_VERSION

# Cross-compiled natively, like the relay.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/usr/local/bin/api ./cmd/api \
	&& mkdir -p /out/data /out/tmp

FROM gcr.io/distroless/static-debian12:nonroot
# /data holds the databases (a volume, which gets this ownership when it is
# first made); /tmp holds the start marker, which must not outlive the
# container. deploy/compose.yaml sets both paths.
COPY --from=build --chown=nonroot:nonroot /out/ /
USER nonroot
# The backend's default ADDR (server/internal/config/config.go).
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/api"]
