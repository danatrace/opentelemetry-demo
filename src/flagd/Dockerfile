FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine AS builder

ARG TARGETOS
ARG TARGETARCH
ARG FLAGD_COMMIT=c0a2940aef33f8558aa6ea4941ded74f0a6f6e83

RUN apk add --no-cache git

WORKDIR /src

RUN git init && \
    git remote add origin https://github.com/open-feature/flagd.git && \
    git fetch --depth 1 origin "$FLAGD_COMMIT" && \
    git checkout --detach FETCH_HEAD

ENV GOTOOLCHAIN=local

RUN go work init ./core ./flagd && go mod download

RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags "-X main.version=0.12.8 -X main.commit=${FLAGD_COMMIT}" \
    -o /bin/flagd-build flagd/main.go

RUN go version -m /bin/flagd-build | grep -F 'go1.27.3'

FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /bin/flagd-build .
ENTRYPOINT ["/flagd-build"]