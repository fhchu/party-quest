# The WebTransport relay. Mount a real certificate and pass -cert and -key;
# without them it makes a self-signed one for local testing.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /relay .

FROM gcr.io/distroless/static-debian12
COPY --from=build /relay /relay
EXPOSE 9080/udp 9080/tcp
ENTRYPOINT ["/relay"]
