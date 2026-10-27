FROM golang:1.27.3-alpine3.23 AS build

RUN apk add --no-cache gcc libc-dev

WORKDIR /build

COPY ["src/go.*", "./"]

RUN go mod download

COPY ["src/", "."]

RUN go build -ldflags="-linkmode=external" -o load-generator

FROM alpine:3.22

WORKDIR /app

COPY --from=build ["/build/load-generator", "."]

CMD ["/app/load-generator"]
