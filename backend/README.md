# Backend (Phase 1: schema and models)

Python 3.12+, FastAPI, PostgreSQL, SQLAlchemy 2.0 async, Alembic, Redis, Celery. See `docs/architecture/01-blueprint.md`.

```bash
cd backend && pip install -e ".[dev]"
pytest                                   # structural invariants (no database needed)
TEST_DATABASE_URL="postgresql+psycopg://user@host/db" pytest   # also runs real-PostgreSQL constraint tests (drops and recreates schema public)
```
Warning: the database tests run `DROP SCHEMA public CASCADE`. Point them only at a throwaway database.
