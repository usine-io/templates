#!/usr/bin/env bash
# Génère les 5 secrets pour infra/.env (alphabet URL-safe + JSON-safe).
# Usage :
#   ./generate.sh                         # imprime sur stdout
#   ./generate.sh >> ../../infra/.env     # ajoute à infra/.env (vérifier qu'elles n'y sont pas déjà !)
#
# Cf. INC-2026-05-05 (spark-kit/spark-kit/INCIDENTS.md) pour le pourquoi de cet alphabet.

set -euo pipefail

gen() {
    LC_ALL=C tr -dc 'A-Za-z0-9-_' </dev/urandom | head -c 32
    echo
}

cat <<EOF
POSTGRES_ROOT_PASSWORD=$(gen)
N8N_DB_PASSWORD=$(gen)
NOCODB_DB_PASSWORD=$(gen)
N8N_ENCRYPTION_KEY=$(gen)
NC_AUTH_JWT_SECRET=$(gen)
EOF
