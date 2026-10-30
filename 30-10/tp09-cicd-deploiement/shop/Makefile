M ?= 002-add-sku.sql

.PHONY: secrets up prod-up migrate test down

secrets:
	mkdir -p secrets
	@if [ ! -f secrets/db_password.txt ]; then openssl rand -hex 24 > secrets/db_password.txt; chmod 600 secrets/db_password.txt; fi
	@if [ ! -f secrets/pip.conf ]; then printf '%s\n' '[global]' 'index-url = https://pypi.org/simple' > secrets/pip.conf; fi

up: secrets
	docker compose up -d --wait

prod-up: secrets
	docker compose -f compose.yml -f compose.prod.yml up -d --wait

migrate: secrets
	MIGRATION=$(M) docker compose run --rm migrate

test:
	./smoke-test.sh

down:
	docker compose down
