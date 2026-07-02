# Build stage
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o vpn_api .

# Run stage
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/vpn_api .
EXPOSE 8080
CMD ["./vpn_api"]
