FROM postgres:15

COPY docker/init/ /docker-entrypoint-initdb.d/
