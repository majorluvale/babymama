#!/bin/sh
set -e

# Apply migrations when they exist, otherwise sync the schema (first start of a fresh project).
if [ -d prisma/migrations ]; then
  npx prisma migrate deploy
else
  npx prisma db push --skip-generate
fi

if [ "$RUN_SEED" = "true" ]; then
  npx tsx prisma/seed.ts || echo "Seed skipped"
fi

exec node dist/index.js
