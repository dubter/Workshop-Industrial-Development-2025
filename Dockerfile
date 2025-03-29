FROM golang:1.17-alpine AS builder

WORKDIR /app
COPY main.go .
RUN go mod init app-logger && \
    go build -o app-logger .

FROM alpine:3.15

WORKDIR /app
COPY --from=builder /app/app-logger /app/
RUN mkdir -p /app/logs /app/config

# Переменные окружения по умолчанию
ENV APP_PORT=8080
ENV WELCOME_MESSAGE="Welcome to the custom app"
ENV LOG_LEVEL=INFO

EXPOSE 8080
CMD ["/app/app-logger"]