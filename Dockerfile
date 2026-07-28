FROM crystallang/crystal:1.21-alpine AS builder
WORKDIR /build
COPY src ./src
RUN crystal build src/main.cr -o /activity-weather --release --static --no-debug

FROM alpine:3.21
LABEL org.opencontainers.image.source="https://github.com/crystal-actions/activity-weather"
LABEL org.opencontainers.image.description="Render repository activity as a weather report SVG"
LABEL org.opencontainers.image.licenses="MIT"
RUN apk add --no-cache git ca-certificates
COPY --from=builder /activity-weather /usr/local/bin/activity-weather
ENTRYPOINT ["/usr/local/bin/activity-weather"]
