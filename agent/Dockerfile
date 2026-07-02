# Build stage
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o vpn_agent .

# Run stage
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/vpn_agent .
# Template lives outside /app/xray because that dir is a bind-mount at runtime.
COPY xray/config.template.json ./config.template.json
ENV XRAY_TEMPLATE_PATH=/app/config.template.json
CMD ["./vpn_agent"]
