"""Runs the real DDL against PostgreSQL and proves the money/booking constraints reject bad data.
Set TEST_DATABASE_URL=postgresql+psycopg://user@host:port/db to enable (skipped otherwise)."""
import datetime as dt
import os
import uuid
from decimal import Decimal

import pytest
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError

from app.db.base import uuid7
from app.models import Base

URL = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not URL, reason="TEST_DATABASE_URL not set")


@pytest.fixture(scope="module")
def eng():
    e = sa.create_engine(URL)
    with e.begin() as c:
        c.execute(sa.text("DROP SCHEMA public CASCADE; CREATE SCHEMA public"))
    Base.metadata.create_all(e)
    yield e
    e.dispose()


def _org(c, code="AG-1"):
    oid = uuid7()
    c.execute(sa.text("INSERT INTO organizations (id,path,depth,org_type,agent_code,name,legal_name,status,base_currency,timezone,settings,on_watchlist)"
                      " VALUES (:i,:p,0,'parent',:c,'n','n','active','BDT','Asia/Dhaka','{}',false)"), dict(i=oid, p=f"/{oid}/", c=code))
    return oid


def _user(c, org, email="a@b.c"):
    uid = uuid7()
    c.execute(sa.text("INSERT INTO users (id,organization_id,user_type,email,email_norm,password_hash,status,full_name,mfa_method,failed_login_count,token_version)"
                      " VALUES (:i,:o,'b2b',:e,:e,'x','active','n','email',0,0)"), dict(i=uid, o=org, e=email))
    return uid


def _acct(c, org):
    aid = uuid7()
    c.execute(sa.text("INSERT INTO accounts (id,organization_id,code,name,account_type,kind,currency,is_postable) VALUES (:i,:o,'2100','w','liability','wallet','BDT',true)"), dict(i=aid, o=org))
    return aid


def test_wallet_cannot_be_overdrawn_beyond_credit_limit(eng):
    with eng.begin() as c:
        org = _org(c, "W-1"); acct = _acct(c, org)
        c.execute(sa.text("INSERT INTO wallets (id,organization_id,account_id,currency,balance,credit_limit,held_amount,status,version_id) VALUES (:i,:o,:a,'BDT',100.00,50.00,0,'active',1)"),
                  dict(i=uuid7(), o=org, a=acct))
    with pytest.raises(IntegrityError):
        with eng.begin() as c:
            c.execute(sa.text("UPDATE wallets SET balance = -50.01"))   # -50.01 + 50.00 < 0


def test_ledger_line_must_be_one_sided_and_positive(eng):
    with eng.begin() as c:
        org = _org(c, "L-1"); acct = _acct(c, org); jid = uuid7()
        c.execute(sa.text("INSERT INTO journal_entries (id,organization_id,txn_ref,kind,status) VALUES (:i,:o,'T1','deposit','posted')"), dict(i=jid, o=org))
    for dr, cr in [(10, 10), (0, 0), (-5, 0)]:
        with pytest.raises(IntegrityError):
            with eng.begin() as c:
                c.execute(sa.text("INSERT INTO ledger_entries (organization_id,journal_id,account_id,debit,credit,currency) VALUES (:o,:j,:a,:d,:c,'BDT')"),
                          dict(o=org, j=jid, a=acct, d=dr, c=cr))
    with eng.begin() as c:
        c.execute(sa.text("INSERT INTO ledger_entries (organization_id,journal_id,account_id,debit,credit,currency) VALUES (:o,:j,:a,10.00,0,'BDT')"), dict(o=org, j=jid, a=acct))


def test_money_keeps_exact_paisa(eng):
    with eng.begin() as c:
        org = _org(c, "M-1"); acct = _acct(c, org)
        c.execute(sa.text("INSERT INTO wallets (id,organization_id,account_id,currency,balance,credit_limit,held_amount,status,version_id) VALUES (:i,:o,:a,'BDT',0.10,0,0,'active',1)"), dict(i=uuid7(), o=org, a=acct))
        c.execute(sa.text("UPDATE wallets SET balance = balance + 0.20 WHERE organization_id=:o"), dict(o=org))
        assert c.execute(sa.text("SELECT balance FROM wallets WHERE organization_id=:o"), dict(o=org)).scalar() == Decimal("0.30")


def _booking(c, org, user, ref, key, dedupe=None, status="hold", pnr=None):
    c.execute(sa.text("INSERT INTO bookings (id,organization_id,booking_ref,kind,status,booked_by_user_id,direction,currency,total_amount,offer_snapshot,idempotency_key,dedupe_key,supplier_pnr,version_id)"
                      " VALUES (:i,:o,:r,'flight',:s,:u,'none','BDT',100.00,'{}',:k,:d,:p,1)"), dict(i=uuid7(), o=org, r=ref, s=status, u=user, k=key, d=dedupe, p=pnr))


def test_duplicate_active_booking_for_same_pax_and_flight_is_rejected_but_cancelled_one_is_not_a_blocker(eng):
    with eng.begin() as c:
        org = _org(c, "B-1"); u = _user(c, org)
        _booking(c, org, u, "BK1", "k1", dedupe="abc")
    with pytest.raises(IntegrityError):
        with eng.begin() as c:
            _booking(c, org, u, "BK2", "k2", dedupe="abc")                 # double booking, different retry key
    with eng.begin() as c:
        c.execute(sa.text("UPDATE bookings SET status='cancelled' WHERE booking_ref='BK1'"))
        _booking(c, org, u, "BK3", "k3", dedupe="abc")                     # allowed after the first is cancelled


def test_same_idempotency_key_cannot_create_two_bookings(eng):
    with eng.begin() as c:
        org = _org(c, "B-2"); u = _user(c, org, "x@y.z")
        _booking(c, org, u, "BK10", "same")
    with pytest.raises(IntegrityError):
        with eng.begin() as c:
            _booking(c, org, u, "BK11", "same")


def test_bkash_trxid_cannot_be_reused_for_two_deposits(eng):
    with eng.begin() as c:
        org = _org(c, "D-1"); u = _user(c, org, "d@d.d"); acct = _acct(c, org); wid = uuid7()
        c.execute(sa.text("INSERT INTO wallets (id,organization_id,account_id,currency,balance,credit_limit,held_amount,status,version_id) VALUES (:i,:o,:a,'BDT',0,0,0,'active',1)"), dict(i=wid, o=org, a=acct))
        q = "INSERT INTO deposit_requests (id,organization_id,wallet_id,requested_by,amount,method,reference_no,status) VALUES (:i,:o,:w,:u,500.00,'bkash','TRX123','pending')"
        c.execute(sa.text(q), dict(i=uuid7(), o=org, w=wid, u=u))
    with pytest.raises(IntegrityError):
        with eng.begin() as c:
            c.execute(sa.text(q), dict(i=uuid7(), o=org, w=wid, u=u))


def test_partitioned_log_tables_exist_as_partitioned(eng):
    with eng.connect() as c:
        rows = c.execute(sa.text("SELECT relname FROM pg_class WHERE relkind='p' ORDER BY 1")).scalars().all()
    assert rows == ["audit_logs", "search_request_logs", "supplier_api_logs"]
