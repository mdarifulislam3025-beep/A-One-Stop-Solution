"""Import every model so Alembic autogenerate and tests see the full metadata."""
from app.db.base import Base  # noqa: F401
from app.core import models as _core  # noqa: F401
from app.modules.users import models as _users  # noqa: F401
from app.modules.erp import models as _erp  # noqa: F401
from app.modules.ota import models as _ota  # noqa: F401
