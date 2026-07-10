FROM alpine:3.20
RUN apk add --no-cache curl
WORKDIR /app
COPY run.sh .
RUN chmod +x run.sh
CMD ["./run.sh"]
