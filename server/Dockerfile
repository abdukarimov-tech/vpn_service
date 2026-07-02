# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o vpn_api main.go db.go xray_manager.go

# Run stage
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/vpn_api .
COPY xray/config.template.json ./xray/config.template.json
EXPOSE 8080
CMD ["./vpn_api"]
