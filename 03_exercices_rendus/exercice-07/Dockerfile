FROM mysql:8.0

ENV MYSQL_ROOT_PASSWORD=rootpass \
    MYSQL_DATABASE=kennelDB

# Scripts exécutés au premier démarrage (volume vide)
COPY init/ /docker-entrypoint-initdb.d/

EXPOSE 3306
