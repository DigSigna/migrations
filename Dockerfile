FROM migrate/migrate:v4.17.0

WORKDIR /app

COPY migrations /migrations
COPY scripts/migrate.sh /migrate.sh

RUN chmod +x /migrate.sh

ENTRYPOINT ["/migrate.sh"]