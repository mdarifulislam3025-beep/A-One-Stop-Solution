"""Identity + tenancy: organizations (tenant tree), RBAC, users, B2C profiles, B2B KYC, loyalty, admin agent-desk operations."""
from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, ForeignKey, Index, Integer, LargeBinary, String,
                        Text, UniqueConstraint, func, text)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, PkMixin, TenantMixin, TimestampMixin, E, uuid7
from app.db.enums import (AgentOpType, KycStatus, MfaMethod, OrgStatus, OrgType, RoleCode, UserStatus, UserType)


class Organization(Base, PkMixin, TimestampMixin):
    """The tenant tree: Parent -> Sister Concerns -> B2B agencies -> sub-agents / corporate clients; B2C storefronts hang off a concern.
    `path` is a materialized path ('/<root>/<child>/') so "all descendants of X" is one indexed prefix scan."""
    __tablename__ = "organizations"
    parent_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="RESTRICT"))
    path: Mapped[str] = mapped_column(String(512))
    depth: Mapped[int] = mapped_column(Integer, default=0)
    org_type: Mapped[OrgType] = mapped_column(E(OrgType))
    agent_code: Mapped[str] = mapped_column(String(24))          # the human "Agent ID" searched in the admin desk
    name: Mapped[str] = mapped_column(String(200))
    legal_name: Mapped[str] = mapped_column(String(250))          # read-only for agencies; System Admin only
    status: Mapped[OrgStatus] = mapped_column(E(OrgStatus), default=OrgStatus.PENDING)
    suspend_reason: Mapped[str | None] = mapped_column(Text)
    on_watchlist: Mapped[bool] = mapped_column(Boolean, default=False, server_default=text("false"))
    base_currency: Mapped[str] = mapped_column(String(3), default="BDT")
    timezone: Mapped[str] = mapped_column(String(48), default="Asia/Dhaka")
    settings: Mapped[dict] = mapped_column(default=dict, server_default=text("'{}'::jsonb"))
    __table_args__ = (
        UniqueConstraint("agent_code"),
        Index("ix_organizations_path", "path", postgresql_ops={"path": "text_pattern_ops"}),
        Index("ix_organizations_parent_id", "parent_id"),
        Index("ix_organizations_type_status", "org_type", "status"),
        # trigram index for desk name search is added in the Alembic migration (needs pg_trgm extension)
    )


class OrgProfile(Base):
    __tablename__ = "org_profiles"
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), primary_key=True)
    trade_license_no: Mapped[str | None] = mapped_column(String(64))
    iata_no: Mapped[str | None] = mapped_column(String(16))
    owner_id_doc_enc: Mapped[bytes | None] = mapped_column(LargeBinary)   # NID/passport number, AES-GCM envelope
    address: Mapped[str | None] = mapped_column(Text)
    phone: Mapped[str | None] = mapped_column(String(24))
    secondary_contact: Mapped[str | None] = mapped_column(String(120))
    logo_storage_key: Mapped[str | None] = mapped_column(String(255))
    kyc_status: Mapped[KycStatus] = mapped_column(E(KycStatus), default=KycStatus.SUBMITTED)
    approved_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    approved_at: Mapped[dt.datetime | None]


class OrgKycDocument(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "org_kyc_documents"
    doc_type: Mapped[str] = mapped_column(String(32))                    # trade_license, nid, passport, tin ...
    storage_key: Mapped[str] = mapped_column(String(255))
    sha256: Mapped[str] = mapped_column(String(64))
    status: Mapped[KycStatus] = mapped_column(E(KycStatus), default=KycStatus.SUBMITTED)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    reviewed_at: Mapped[dt.datetime | None]


class Role(Base, PkMixin):
    __tablename__ = "roles"
    code: Mapped[RoleCode] = mapped_column(E(RoleCode), unique=True)
    name: Mapped[str] = mapped_column(String(80))


class Permission(Base, PkMixin):
    __tablename__ = "permissions"
    code: Mapped[str] = mapped_column(String(80), unique=True)           # e.g. "booking.issue", "ledger.read", "agent.suspend"
    description: Mapped[str | None] = mapped_column(String(255))


class RolePermission(Base):
    __tablename__ = "role_permissions"
    role_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True)
    permission_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("permissions.id", ondelete="CASCADE"), primary_key=True)


class User(Base, PkMixin, TenantMixin, TimestampMixin):
    """One table for staff, B2B agents and B2C customers (1M+ rows). organization_id = home tenant (B2C: the storefront)."""
    __tablename__ = "users"
    user_type: Mapped[UserType] = mapped_column(E(UserType))
    username: Mapped[str | None] = mapped_column(String(64))
    email: Mapped[str] = mapped_column(String(254))
    email_norm: Mapped[str] = mapped_column(String(254))                 # lower(trim(email)); uniqueness is on this
    phone_e164: Mapped[str | None] = mapped_column(String(20))
    password_hash: Mapped[str] = mapped_column(String(255))              # argon2id
    status: Mapped[UserStatus] = mapped_column(E(UserStatus), default=UserStatus.ACTIVE)
    full_name: Mapped[str] = mapped_column(String(160))
    mfa_method: Mapped[MfaMethod] = mapped_column(E(MfaMethod), default=MfaMethod.EMAIL)
    totp_secret_enc: Mapped[bytes | None] = mapped_column(LargeBinary)   # shown once at enrolment, never at sign-in
    failed_login_count: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[dt.datetime | None]
    email_verified_at: Mapped[dt.datetime | None]
    phone_verified_at: Mapped[dt.datetime | None]
    last_login_at: Mapped[dt.datetime | None]
    token_version: Mapped[int] = mapped_column(Integer, default=0)       # bump to revoke all JWTs
    __table_args__ = (
        UniqueConstraint("organization_id", "email_norm"),
        Index("ix_users_phone_e164", "phone_e164"),
        Index("ix_users_username", "username"),
        Index("ix_users_org_type_created", "organization_id", "user_type", "created_at"),
    )


class UserOrgRole(Base, PkMixin):
    """RBAC grant: this user holds this role inside this org (and, by path prefix, its descendants)."""
    __tablename__ = "user_org_roles"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    role_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("roles.id", ondelete="RESTRICT"))
    granted_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())
    __table_args__ = (UniqueConstraint("user_id", "organization_id", "role_id"), Index("ix_user_org_roles_org", "organization_id"))


class MfaBackupCode(Base, PkMixin, TenantMixin):
    __tablename__ = "mfa_backup_codes"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    code_hash: Mapped[str] = mapped_column(String(128))
    used_at: Mapped[dt.datetime | None]


class B2CProfile(Base, TenantMixin, TimestampMixin):
    __tablename__ = "b2c_profiles"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    first_name: Mapped[str] = mapped_column(String(80))
    last_name: Mapped[str] = mapped_column(String(80))
    date_of_birth: Mapped[dt.date | None] = mapped_column(Date)
    nationality: Mapped[str | None] = mapped_column(String(2))
    passport_no_enc: Mapped[bytes | None] = mapped_column(LargeBinary)   # app-level AES-GCM; never plaintext
    passport_no_hash: Mapped[bytes | None] = mapped_column(LargeBinary(32))  # HMAC for equality lookup / dedupe only
    passport_expiry: Mapped[dt.date | None] = mapped_column(Date)
    pii_key_id: Mapped[str | None] = mapped_column(String(32))           # key rotation
    preferred_language: Mapped[str] = mapped_column(String(8), default="en")
    marketing_opt_in: Mapped[bool] = mapped_column(Boolean, default=False)
    referral_code: Mapped[str | None] = mapped_column(String(16), unique=True)


class Traveller(Base, PkMixin, TenantMixin, TimestampMixin):
    """Saved passengers on a user's account."""
    __tablename__ = "travellers"
    owner_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    pax_type: Mapped[str] = mapped_column(String(3))
    title: Mapped[str | None] = mapped_column(String(8))
    first_name: Mapped[str] = mapped_column(String(80))
    last_name: Mapped[str] = mapped_column(String(80))
    date_of_birth: Mapped[dt.date] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(1))
    nationality: Mapped[str | None] = mapped_column(String(2))
    passport_no_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    passport_no_hash: Mapped[bytes | None] = mapped_column(LargeBinary(32))
    passport_expiry: Mapped[dt.date | None] = mapped_column(Date)


class LoyaltyAccount(Base, TenantMixin, TimestampMixin):
    __tablename__ = "loyalty_accounts"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    points_balance: Mapped[int] = mapped_column(BigInteger, default=0)
    tier: Mapped[str] = mapped_column(String(16), default="base")
    __table_args__ = (CheckConstraint("points_balance >= 0", name="points_non_negative"),)


class LoyaltyLedger(Base, TenantMixin):
    __tablename__ = "loyalty_ledger"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    delta: Mapped[int] = mapped_column(BigInteger)
    reason: Mapped[str] = mapped_column(String(64))
    booking_id: Mapped[uuid.UUID | None]                                  # soft ref (bookings module)
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())
    __table_args__ = (Index("ix_loyalty_ledger_user_id", "user_id", "id"),)


class AgentOp(Base, PkMixin, TenantMixin):
    """Admin 'Others' desk: every warning/suspension/watchlist/note/2FA-reset is a row with a unique operation id.
    organization_id = the agency acted upon."""
    __tablename__ = "agent_ops"
    op_id: Mapped[str] = mapped_column(String(32), unique=True)           # unique identifying value required for every operation
    op_type: Mapped[AgentOpType] = mapped_column(E(AgentOpType))
    target_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    actor_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    reason: Mapped[str | None] = mapped_column(Text)
    payload: Mapped[dict] = mapped_column(default=dict, server_default=text("'{}'::jsonb"))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())
    __table_args__ = (Index("ix_agent_ops_org_created", "organization_id", "created_at"),)
