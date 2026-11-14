-- Generated from SQLAlchemy models (PostgreSQL). Reference only; Alembic is the source of truth.

CREATE TABLE airlines (
	iata_code VARCHAR(3) NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	country VARCHAR(2), 
	is_lcc BOOLEAN NOT NULL, 
	one_way_fare_combinable BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	CONSTRAINT pk_airlines PRIMARY KEY (id), 
	CONSTRAINT uq_airlines_iata_code UNIQUE (iata_code)
);

CREATE TABLE airports (
	iata_code VARCHAR(3) NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	city VARCHAR(80) NOT NULL, 
	country VARCHAR(2) NOT NULL, 
	latitude FLOAT NOT NULL, 
	longitude FLOAT NOT NULL, 
	timezone VARCHAR(48), 
	id UUID NOT NULL, 
	CONSTRAINT pk_airports PRIMARY KEY (id), 
	CONSTRAINT uq_airports_iata_code UNIQUE (iata_code)
);

CREATE INDEX ix_airports_lat_lon ON airports (latitude, longitude);

CREATE INDEX ix_airports_city ON airports (city);

CREATE TABLE organizations (
	parent_id UUID, 
	path VARCHAR(512) NOT NULL, 
	depth INTEGER NOT NULL, 
	org_type VARCHAR(32) NOT NULL, 
	agent_code VARCHAR(24) NOT NULL, 
	name VARCHAR(200) NOT NULL, 
	legal_name VARCHAR(250) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	suspend_reason TEXT, 
	on_watchlist BOOLEAN DEFAULT false NOT NULL, 
	base_currency VARCHAR(3) NOT NULL, 
	timezone VARCHAR(48) NOT NULL, 
	settings JSONB DEFAULT '{}'::jsonb NOT NULL, 
	id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_organizations PRIMARY KEY (id), 
	CONSTRAINT uq_organizations_agent_code UNIQUE (agent_code), 
	CONSTRAINT fk_organizations_parent_id_organizations FOREIGN KEY(parent_id) REFERENCES organizations (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_organizations_orgtype CHECK (org_type IN ('parent', 'sister_concern', 'b2b_agency', 'sub_agent', 'corporate_client', 'b2c_storefront')), 
	CONSTRAINT ck_organizations_orgstatus CHECK (status IN ('pending', 'active', 'suspended', 'closed'))
);

CREATE INDEX ix_organizations_type_status ON organizations (org_type, status);

CREATE INDEX ix_organizations_path ON organizations (path text_pattern_ops);

CREATE INDEX ix_organizations_parent_id ON organizations (parent_id);

CREATE TABLE permissions (
	code VARCHAR(80) NOT NULL, 
	description VARCHAR(255), 
	id UUID NOT NULL, 
	CONSTRAINT pk_permissions PRIMARY KEY (id), 
	CONSTRAINT uq_permissions_code UNIQUE (code)
);

CREATE TABLE roles (
	code VARCHAR(32) NOT NULL, 
	name VARCHAR(80) NOT NULL, 
	id UUID NOT NULL, 
	CONSTRAINT pk_roles PRIMARY KEY (id), 
	CONSTRAINT uq_roles_code UNIQUE (code), 
	CONSTRAINT ck_roles_rolecode CHECK (code IN ('super_admin', 'sister_admin', 'accountant', 'agency_owner', 'b2b_agent', 'b2c_customer'))
);

CREATE TABLE suppliers (
	code VARCHAR(24) NOT NULL, 
	name VARCHAR(80) NOT NULL, 
	kind VARCHAR(32) NOT NULL, 
	id UUID NOT NULL, 
	CONSTRAINT pk_suppliers PRIMARY KEY (id), 
	CONSTRAINT uq_suppliers_code UNIQUE (code), 
	CONSTRAINT ck_suppliers_supplierkind CHECK (kind IN ('gds', 'ndc', 'consolidator', 'aggregator', 'hotel'))
);

CREATE TABLE accounts (
	code VARCHAR(32) NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	account_type VARCHAR(32) NOT NULL, 
	kind VARCHAR(32) NOT NULL, 
	parent_id UUID, 
	currency VARCHAR(3) NOT NULL, 
	is_postable BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_accounts PRIMARY KEY (id), 
	CONSTRAINT uq_accounts_organization_id_code UNIQUE (organization_id, code), 
	CONSTRAINT ck_accounts_accounttype CHECK (account_type IN ('asset', 'liability', 'equity', 'income', 'expense')), 
	CONSTRAINT ck_accounts_accountkind CHECK (kind IN ('normal', 'wallet', 'receivable', 'payable', 'tax', 'clearing')), 
	CONSTRAINT fk_accounts_parent_id_accounts FOREIGN KEY(parent_id) REFERENCES accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_accounts_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_accounts_organization_id ON accounts (organization_id);

CREATE TABLE audit_logs (
	id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	actor_user_id UUID, 
	action VARCHAR(64) NOT NULL, 
	entity_type VARCHAR(48) NOT NULL, 
	entity_id VARCHAR(64), 
	ip INET, 
	user_agent VARCHAR(255), 
	request_id VARCHAR(48), 
	before JSONB, 
	after JSONB, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_audit_logs PRIMARY KEY (id, created_at), 
	CONSTRAINT fk_audit_logs_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
)
 PARTITION BY RANGE (created_at);

CREATE INDEX ix_audit_logs_entity ON audit_logs (entity_type, entity_id);

CREATE INDEX ix_audit_logs_organization_id ON audit_logs (organization_id);

CREATE INDEX ix_audit_logs_org_created ON audit_logs (organization_id, created_at);

CREATE TABLE fx_rates (
	base_ccy VARCHAR(3) NOT NULL, 
	quote_ccy VARCHAR(3) NOT NULL, 
	rate NUMERIC(9, 6) NOT NULL, 
	source VARCHAR(40) NOT NULL, 
	as_of TIMESTAMP WITH TIME ZONE NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_fx_rates PRIMARY KEY (id), 
	CONSTRAINT ck_fx_rates_positive CHECK (rate > 0), 
	CONSTRAINT fk_fx_rates_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_fx_rates_pair ON fx_rates (organization_id, base_ccy, quote_ccy, as_of);

CREATE INDEX ix_fx_rates_organization_id ON fx_rates (organization_id);

CREATE TABLE group_fares (
	code VARCHAR(32) NOT NULL, 
	airline_id UUID NOT NULL, 
	origin VARCHAR(3) NOT NULL, 
	destination VARCHAR(3) NOT NULL, 
	departs_on DATE NOT NULL, 
	seats_total INTEGER NOT NULL, 
	seats_sold INTEGER NOT NULL, 
	fixed_fare NUMERIC(12, 2) NOT NULL, 
	deposit_due_at TIMESTAMP WITH TIME ZONE, 
	ticketing_deadline_at TIMESTAMP WITH TIME ZONE, 
	terms TEXT, 
	status VARCHAR(32) NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_group_fares PRIMARY KEY (id), 
	CONSTRAINT uq_group_fares_organization_id_code UNIQUE (organization_id, code), 
	CONSTRAINT ck_group_fares_quota CHECK (seats_sold >= 0 AND seats_sold <= seats_total), 
	CONSTRAINT fk_group_fares_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_group_fares_groupstatus CHECK (status IN ('open', 'closed', 'cancelled')), 
	CONSTRAINT fk_group_fares_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_group_fares_organization_id ON group_fares (organization_id);

CREATE TABLE idempotency_keys (
	scope VARCHAR(48) NOT NULL, 
	key VARCHAR(80) NOT NULL, 
	request_hash VARCHAR(64) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	response_code SMALLINT, 
	response_body JSONB, 
	resource_type VARCHAR(32), 
	resource_id UUID, 
	locked_until TIMESTAMP WITH TIME ZONE, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	expires_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_idempotency_keys PRIMARY KEY (id), 
	CONSTRAINT uq_idempotency_keys_organization_id_scope_key UNIQUE (organization_id, scope, key), 
	CONSTRAINT ck_idempotency_keys_idemstatus CHECK (status IN ('in_progress', 'completed', 'failed')), 
	CONSTRAINT fk_idempotency_keys_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_idempotency_keys_expires ON idempotency_keys (expires_at);

CREATE INDEX ix_idempotency_keys_organization_id ON idempotency_keys (organization_id);

CREATE TABLE markup_rules (
	scope VARCHAR(32) NOT NULL, 
	agency_org_id UUID, 
	airline_id UUID, 
	origin VARCHAR(3), 
	destination VARCHAR(3), 
	kind VARCHAR(32) NOT NULL, 
	value NUMERIC(9, 6) NOT NULL, 
	valid_from DATE, 
	valid_to DATE, 
	priority INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_markup_rules PRIMARY KEY (id), 
	CONSTRAINT ck_markup_rules_markupscope CHECK (scope IN ('global', 'agency', 'airline', 'route')), 
	CONSTRAINT fk_markup_rules_agency_org_id_organizations FOREIGN KEY(agency_org_id) REFERENCES organizations (id) ON DELETE CASCADE, 
	CONSTRAINT fk_markup_rules_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_markup_rules_amountkind CHECK (kind IN ('fixed', 'percent')), 
	CONSTRAINT fk_markup_rules_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_markup_rules_lookup ON markup_rules (organization_id, scope, airline_id, origin, destination);

CREATE INDEX ix_markup_rules_organization_id ON markup_rules (organization_id);

CREATE TABLE ota_settings (
	organization_id UUID NOT NULL, 
	show_branded_fares BOOLEAN NOT NULL, 
	best_buy_min_bag_kg SMALLINT NOT NULL, 
	mixed_airlines_enabled BOOLEAN NOT NULL, 
	mix_require_same_source BOOLEAN NOT NULL, 
	search_cache_ttl_s INTEGER NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_ota_settings PRIMARY KEY (organization_id), 
	CONSTRAINT fk_ota_settings_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE CASCADE
);

CREATE TABLE outbox_events (
	id BIGSERIAL NOT NULL, 
	topic VARCHAR(64) NOT NULL, 
	payload JSONB NOT NULL, 
	dedupe_key VARCHAR(96), 
	status VARCHAR(32) NOT NULL, 
	attempts INTEGER NOT NULL, 
	next_attempt_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	sent_at TIMESTAMP WITH TIME ZONE, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_outbox_events PRIMARY KEY (id), 
	CONSTRAINT ck_outbox_events_outboxstatus CHECK (status IN ('pending', 'sent', 'failed')), 
	CONSTRAINT fk_outbox_events_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_outbox_events_pending ON outbox_events (next_attempt_at) WHERE status = 'pending';

CREATE INDEX ix_outbox_events_organization_id ON outbox_events (organization_id);

CREATE UNIQUE INDEX uq_outbox_events_dedupe ON outbox_events (dedupe_key) WHERE dedupe_key IS NOT NULL;

CREATE TABLE payment_events (
	organization_id UUID, 
	provider VARCHAR(32) NOT NULL, 
	event_id VARCHAR(96) NOT NULL, 
	payload JSONB NOT NULL, 
	received_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	processed_at TIMESTAMP WITH TIME ZONE, 
	id UUID NOT NULL, 
	CONSTRAINT pk_payment_events PRIMARY KEY (id), 
	CONSTRAINT uq_payment_events_provider_event_id UNIQUE (provider, event_id), 
	CONSTRAINT fk_payment_events_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_payment_events_payprovider CHECK (provider IN ('sslcommerz', 'bkash', 'nagad', 'stripe', 'paypal'))
);

CREATE INDEX ix_payment_events_organization_id ON payment_events (organization_id);

CREATE TABLE role_permissions (
	role_id UUID NOT NULL, 
	permission_id UUID NOT NULL, 
	CONSTRAINT pk_role_permissions PRIMARY KEY (role_id, permission_id), 
	CONSTRAINT fk_role_permissions_role_id_roles FOREIGN KEY(role_id) REFERENCES roles (id) ON DELETE CASCADE, 
	CONSTRAINT fk_role_permissions_permission_id_permissions FOREIGN KEY(permission_id) REFERENCES permissions (id) ON DELETE CASCADE
);

CREATE TABLE search_request_logs (
	id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	user_id UUID, 
	origin VARCHAR(3) NOT NULL, 
	destination VARCHAR(3) NOT NULL, 
	depart_on DATE NOT NULL, 
	pax_count SMALLINT NOT NULL, 
	cache_hit BOOLEAN NOT NULL, 
	offers_count INTEGER NOT NULL, 
	latency_ms INTEGER NOT NULL, 
	supplier_breakdown JSONB, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_search_request_logs PRIMARY KEY (id, created_at), 
	CONSTRAINT fk_search_request_logs_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
)
 PARTITION BY RANGE (created_at);

CREATE INDEX ix_search_request_logs_org_created ON search_request_logs (organization_id, created_at);

CREATE INDEX ix_search_request_logs_organization_id ON search_request_logs (organization_id);

CREATE TABLE service_charge_rules (
	charge_type VARCHAR(32) NOT NULL, 
	agency_org_id UUID, 
	fixed_amount NUMERIC(12, 2) NOT NULL, 
	pct NUMERIC(9, 6) NOT NULL, 
	min_amount NUMERIC(12, 2), 
	max_amount NUMERIC(12, 2), 
	is_active BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_service_charge_rules PRIMARY KEY (id), 
	CONSTRAINT ck_service_charge_rules_chargetype CHECK (charge_type IN ('flight_domestic', 'flight_intl', 'reissue', 'refund', 'void')), 
	CONSTRAINT fk_service_charge_rules_agency_org_id_organizations FOREIGN KEY(agency_org_id) REFERENCES organizations (id) ON DELETE CASCADE, 
	CONSTRAINT fk_service_charge_rules_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_service_charge_rules_lookup ON service_charge_rules (organization_id, charge_type);

CREATE INDEX ix_service_charge_rules_organization_id ON service_charge_rules (organization_id);

CREATE TABLE supplier_accounts (
	supplier_id UUID NOT NULL, 
	label VARCHAR(80) NOT NULL, 
	office_id VARCHAR(32), 
	credentials_ref VARCHAR(200) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	ticketing_model VARCHAR(32) NOT NULL, 
	consolidator_ref VARCHAR(80), 
	priority INTEGER NOT NULL, 
	rate_limit_rps INTEGER NOT NULL, 
	timeout_ms INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_supplier_accounts PRIMARY KEY (id), 
	CONSTRAINT uq_supplier_accounts_organization_id_supplier_id_label UNIQUE (organization_id, supplier_id, label), 
	CONSTRAINT fk_supplier_accounts_supplier_id_suppliers FOREIGN KEY(supplier_id) REFERENCES suppliers (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_supplier_accounts_ticketingmodel CHECK (ticketing_model IN ('direct', 'consolidator', 'host_agency')), 
	CONSTRAINT fk_supplier_accounts_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_supplier_accounts_organization_id ON supplier_accounts (organization_id);

CREATE TABLE supplier_api_logs (
	id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	supplier_account_id UUID NOT NULL, 
	operation VARCHAR(32) NOT NULL, 
	latency_ms INTEGER NOT NULL, 
	ok BOOLEAN NOT NULL, 
	error_code VARCHAR(48), 
	request_id VARCHAR(48), 
	payload_ref VARCHAR(255), 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_supplier_api_logs PRIMARY KEY (id, created_at), 
	CONSTRAINT fk_supplier_api_logs_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
)
 PARTITION BY RANGE (created_at);

CREATE INDEX ix_supplier_api_logs_acct_created ON supplier_api_logs (supplier_account_id, created_at);

CREATE INDEX ix_supplier_api_logs_organization_id ON supplier_api_logs (organization_id);

CREATE TABLE supplier_indicators (
	supplier_id UUID NOT NULL, 
	label VARCHAR(24) NOT NULL, 
	tone VARCHAR(12) NOT NULL, 
	visible BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_supplier_indicators PRIMARY KEY (id), 
	CONSTRAINT uq_supplier_indicators_organization_id_supplier_id UNIQUE (organization_id, supplier_id), 
	CONSTRAINT fk_supplier_indicators_supplier_id_suppliers FOREIGN KEY(supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE, 
	CONSTRAINT fk_supplier_indicators_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_supplier_indicators_organization_id ON supplier_indicators (organization_id);

CREATE TABLE tax_rules (
	code VARCHAR(16) NOT NULL, 
	rate NUMERIC(9, 6) NOT NULL, 
	base_description VARCHAR(255) NOT NULL, 
	refundable BOOLEAN NOT NULL, 
	valid_from DATE NOT NULL, 
	valid_to DATE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_tax_rules PRIMARY KEY (id), 
	CONSTRAINT uq_tax_rules_organization_id_code_valid_from UNIQUE (organization_id, code, valid_from), 
	CONSTRAINT fk_tax_rules_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_tax_rules_organization_id ON tax_rules (organization_id);

CREATE TABLE users (
	user_type VARCHAR(32) NOT NULL, 
	username VARCHAR(64), 
	email VARCHAR(254) NOT NULL, 
	email_norm VARCHAR(254) NOT NULL, 
	phone_e164 VARCHAR(20), 
	password_hash VARCHAR(255) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	full_name VARCHAR(160) NOT NULL, 
	mfa_method VARCHAR(32) NOT NULL, 
	totp_secret_enc BYTEA, 
	failed_login_count INTEGER NOT NULL, 
	locked_until TIMESTAMP WITH TIME ZONE, 
	email_verified_at TIMESTAMP WITH TIME ZONE, 
	phone_verified_at TIMESTAMP WITH TIME ZONE, 
	last_login_at TIMESTAMP WITH TIME ZONE, 
	token_version INTEGER NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_users PRIMARY KEY (id), 
	CONSTRAINT uq_users_organization_id_email_norm UNIQUE (organization_id, email_norm), 
	CONSTRAINT ck_users_usertype CHECK (user_type IN ('staff', 'b2b', 'b2c')), 
	CONSTRAINT ck_users_userstatus CHECK (status IN ('active', 'locked', 'disabled')), 
	CONSTRAINT ck_users_mfamethod CHECK (mfa_method IN ('off', 'email', 'totp')), 
	CONSTRAINT fk_users_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_users_org_type_created ON users (organization_id, user_type, created_at);

CREATE INDEX ix_users_phone_e164 ON users (phone_e164);

CREATE INDEX ix_users_organization_id ON users (organization_id);

CREATE INDEX ix_users_username ON users (username);

CREATE TABLE agent_ops (
	op_id VARCHAR(32) NOT NULL, 
	op_type VARCHAR(32) NOT NULL, 
	target_user_id UUID, 
	actor_user_id UUID NOT NULL, 
	reason TEXT, 
	payload JSONB DEFAULT '{}'::jsonb NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_agent_ops PRIMARY KEY (id), 
	CONSTRAINT uq_agent_ops_op_id UNIQUE (op_id), 
	CONSTRAINT ck_agent_ops_agentoptype CHECK (op_type IN ('warn', 'suspend', 'reactivate', 'watch_add', 'watch_remove', 'note', 'reset_2fa')), 
	CONSTRAINT fk_agent_ops_target_user_id_users FOREIGN KEY(target_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_agent_ops_actor_user_id_users FOREIGN KEY(actor_user_id) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_agent_ops_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_agent_ops_org_created ON agent_ops (organization_id, created_at);

CREATE INDEX ix_agent_ops_organization_id ON agent_ops (organization_id);

CREATE TABLE airline_mix_rules (
	airline_a_id UUID NOT NULL, 
	airline_b_id UUID NOT NULL, 
	effect VARCHAR(32) NOT NULL, 
	reason VARCHAR(255), 
	created_by UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_airline_mix_rules PRIMARY KEY (id), 
	CONSTRAINT ck_airline_mix_rules_canonical_pair CHECK (airline_a_id < airline_b_id), 
	CONSTRAINT uq_airline_mix_rules_organization_id_airline_a_id_airline_b_id UNIQUE (organization_id, airline_a_id, airline_b_id), 
	CONSTRAINT fk_airline_mix_rules_airline_a_id_airlines FOREIGN KEY(airline_a_id) REFERENCES airlines (id) ON DELETE CASCADE, 
	CONSTRAINT fk_airline_mix_rules_airline_b_id_airlines FOREIGN KEY(airline_b_id) REFERENCES airlines (id) ON DELETE CASCADE, 
	CONSTRAINT ck_airline_mix_rules_mixeffect CHECK (effect IN ('allow', 'block')), 
	CONSTRAINT fk_airline_mix_rules_created_by_users FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_airline_mix_rules_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_airline_mix_rules_organization_id ON airline_mix_rules (organization_id);

CREATE TABLE b2c_profiles (
	user_id UUID NOT NULL, 
	first_name VARCHAR(80) NOT NULL, 
	last_name VARCHAR(80) NOT NULL, 
	date_of_birth DATE, 
	nationality VARCHAR(2), 
	passport_no_enc BYTEA, 
	passport_no_hash BYTEA, 
	passport_expiry DATE, 
	pii_key_id VARCHAR(32), 
	preferred_language VARCHAR(8) NOT NULL, 
	marketing_opt_in BOOLEAN NOT NULL, 
	referral_code VARCHAR(16), 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_b2c_profiles PRIMARY KEY (user_id), 
	CONSTRAINT fk_b2c_profiles_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT uq_b2c_profiles_referral_code UNIQUE (referral_code), 
	CONSTRAINT fk_b2c_profiles_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_b2c_profiles_organization_id ON b2c_profiles (organization_id);

CREATE TABLE bookings (
	booking_ref VARCHAR(20) NOT NULL, 
	kind VARCHAR(32) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	booked_by_user_id UUID NOT NULL, 
	customer_user_id UUID, 
	supplier_account_id UUID, 
	supplier_pnr VARCHAR(12), 
	airline_pnr VARCHAR(12), 
	mix_group_id UUID, 
	direction VARCHAR(32) NOT NULL, 
	parent_booking_id UUID, 
	group_fare_id UUID, 
	currency VARCHAR(3) NOT NULL, 
	total_amount NUMERIC(12, 2) NOT NULL, 
	supplier_cost NUMERIC(12, 2), 
	ticket_time_limit_at TIMESTAMP WITH TIME ZONE, 
	issued_at TIMESTAMP WITH TIME ZONE, 
	cancelled_at TIMESTAMP WITH TIME ZONE, 
	offer_snapshot JSONB DEFAULT '{}'::jsonb NOT NULL, 
	dedupe_key VARCHAR(64), 
	idempotency_key VARCHAR(80) NOT NULL, 
	version_id INTEGER NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_bookings PRIMARY KEY (id), 
	CONSTRAINT ck_bookings_non_negative CHECK (total_amount >= 0), 
	CONSTRAINT uq_bookings_organization_id_idempotency_key UNIQUE (organization_id, idempotency_key), 
	CONSTRAINT uq_bookings_booking_ref UNIQUE (booking_ref), 
	CONSTRAINT ck_bookings_bookingkind CHECK (kind IN ('flight', 'hotel', 'visa', 'package', 'insurance', 'group')), 
	CONSTRAINT ck_bookings_bookingstatus CHECK (status IN ('payment_pending', 'hold', 'partial_payment', 'issue_in_process', 'issued', 'booking_unknown', 'ticketing_unknown', 'manual_review', 'issue_rejected', 'cancelled', 'expired', 'voided', 'refunded', 'reissued')), 
	CONSTRAINT fk_bookings_booked_by_user_id_users FOREIGN KEY(booked_by_user_id) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_bookings_customer_user_id_users FOREIGN KEY(customer_user_id) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_bookings_supplier_account_id_supplier_accounts FOREIGN KEY(supplier_account_id) REFERENCES supplier_accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_bookings_direction CHECK (direction IN ('out', 'ret', 'none')), 
	CONSTRAINT fk_bookings_parent_booking_id_bookings FOREIGN KEY(parent_booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_bookings_group_fare_id_group_fares FOREIGN KEY(group_fare_id) REFERENCES group_fares (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_bookings_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_bookings_org_created ON bookings (organization_id, created_at);

CREATE INDEX ix_bookings_customer ON bookings (customer_user_id, created_at);

CREATE INDEX ix_bookings_mix_group ON bookings (mix_group_id);

CREATE UNIQUE INDEX uq_bookings_supplier_pnr ON bookings (supplier_account_id, supplier_pnr) WHERE supplier_pnr IS NOT NULL;

CREATE INDEX ix_bookings_org_status_created ON bookings (organization_id, status, created_at);

CREATE INDEX ix_bookings_supplier_pnr ON bookings (supplier_pnr);

CREATE INDEX ix_bookings_parent ON bookings (parent_booking_id);

CREATE UNIQUE INDEX uq_bookings_active_dedupe ON bookings (organization_id, dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('hold','partial_payment','issue_in_process','issued');

CREATE INDEX ix_bookings_timelimit_open ON bookings (ticket_time_limit_at) WHERE status IN ('hold','partial_payment');

CREATE INDEX ix_bookings_airline_pnr ON bookings (airline_pnr);

CREATE INDEX ix_bookings_organization_id ON bookings (organization_id);

CREATE TABLE commission_rules (
	agency_org_id UUID, 
	airline_id UUID, 
	route_type VARCHAR(32), 
	cabin_class VARCHAR(2), 
	commission_pct NUMERIC(9, 6) NOT NULL, 
	valid_from DATE NOT NULL, 
	valid_to DATE, 
	priority INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	created_by UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_commission_rules PRIMARY KEY (id), 
	CONSTRAINT ck_commission_rules_pct_range CHECK (commission_pct >= 0 AND commission_pct <= 100), 
	CONSTRAINT fk_commission_rules_agency_org_id_organizations FOREIGN KEY(agency_org_id) REFERENCES organizations (id) ON DELETE CASCADE, 
	CONSTRAINT fk_commission_rules_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_commission_rules_routetype CHECK (route_type IN ('siti', 'soti', 'soto', 'domestic')), 
	CONSTRAINT fk_commission_rules_created_by_users FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_commission_rules_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_commission_rules_lookup ON commission_rules (organization_id, airline_id, route_type, valid_from);

CREATE INDEX ix_commission_rules_organization_id ON commission_rules (organization_id);

CREATE TABLE loyalty_accounts (
	user_id UUID NOT NULL, 
	points_balance BIGINT NOT NULL, 
	tier VARCHAR(16) NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_loyalty_accounts PRIMARY KEY (user_id), 
	CONSTRAINT ck_loyalty_accounts_points_non_negative CHECK (points_balance >= 0), 
	CONSTRAINT fk_loyalty_accounts_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT fk_loyalty_accounts_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_loyalty_accounts_organization_id ON loyalty_accounts (organization_id);

CREATE TABLE loyalty_ledger (
	id BIGSERIAL NOT NULL, 
	user_id UUID NOT NULL, 
	delta BIGINT NOT NULL, 
	reason VARCHAR(64) NOT NULL, 
	booking_id UUID, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_loyalty_ledger PRIMARY KEY (id), 
	CONSTRAINT fk_loyalty_ledger_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT fk_loyalty_ledger_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_loyalty_ledger_user_id ON loyalty_ledger (user_id, id);

CREATE INDEX ix_loyalty_ledger_organization_id ON loyalty_ledger (organization_id);

CREATE TABLE mfa_backup_codes (
	user_id UUID NOT NULL, 
	code_hash VARCHAR(128) NOT NULL, 
	used_at TIMESTAMP WITH TIME ZONE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_mfa_backup_codes PRIMARY KEY (id), 
	CONSTRAINT fk_mfa_backup_codes_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT fk_mfa_backup_codes_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_mfa_backup_codes_user_id ON mfa_backup_codes (user_id);

CREATE INDEX ix_mfa_backup_codes_organization_id ON mfa_backup_codes (organization_id);

CREATE TABLE notifications (
	user_id UUID, 
	channel VARCHAR(32) NOT NULL, 
	template VARCHAR(64) NOT NULL, 
	payload JSONB NOT NULL, 
	status VARCHAR(12) NOT NULL, 
	provider_msg_id VARCHAR(96), 
	sent_at TIMESTAMP WITH TIME ZONE, 
	read_at TIMESTAMP WITH TIME ZONE, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_notifications PRIMARY KEY (id), 
	CONSTRAINT fk_notifications_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT ck_notifications_channel CHECK (channel IN ('email', 'sms', 'whatsapp', 'in_app')), 
	CONSTRAINT fk_notifications_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_notifications_organization_id ON notifications (organization_id);

CREATE INDEX ix_notifications_user_created ON notifications (user_id, created_at);

CREATE TABLE org_kyc_documents (
	doc_type VARCHAR(32) NOT NULL, 
	storage_key VARCHAR(255) NOT NULL, 
	sha256 VARCHAR(64) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	reviewed_by UUID, 
	reviewed_at TIMESTAMP WITH TIME ZONE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_org_kyc_documents PRIMARY KEY (id), 
	CONSTRAINT ck_org_kyc_documents_kycstatus CHECK (status IN ('submitted', 'verified', 'rejected')), 
	CONSTRAINT fk_org_kyc_documents_reviewed_by_users FOREIGN KEY(reviewed_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_org_kyc_documents_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_org_kyc_documents_organization_id ON org_kyc_documents (organization_id);

CREATE TABLE org_profiles (
	organization_id UUID NOT NULL, 
	trade_license_no VARCHAR(64), 
	iata_no VARCHAR(16), 
	owner_id_doc_enc BYTEA, 
	address TEXT, 
	phone VARCHAR(24), 
	secondary_contact VARCHAR(120), 
	logo_storage_key VARCHAR(255), 
	kyc_status VARCHAR(32) NOT NULL, 
	approved_by UUID, 
	approved_at TIMESTAMP WITH TIME ZONE, 
	CONSTRAINT pk_org_profiles PRIMARY KEY (organization_id), 
	CONSTRAINT fk_org_profiles_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE CASCADE, 
	CONSTRAINT ck_org_profiles_kycstatus CHECK (kyc_status IN ('submitted', 'verified', 'rejected')), 
	CONSTRAINT fk_org_profiles_approved_by_users FOREIGN KEY(approved_by) REFERENCES users (id) ON DELETE SET NULL
);

CREATE TABLE reconciliation_runs (
	run_date DATE NOT NULL, 
	started_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	finished_at TIMESTAMP WITH TIME ZONE, 
	items_checked INTEGER NOT NULL, 
	exceptions_found INTEGER NOT NULL, 
	control_total NUMERIC(12, 2), 
	signed_off_by UUID, 
	signed_off_at TIMESTAMP WITH TIME ZONE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_reconciliation_runs PRIMARY KEY (id), 
	CONSTRAINT uq_reconciliation_runs_organization_id_run_date UNIQUE (organization_id, run_date), 
	CONSTRAINT fk_reconciliation_runs_signed_off_by_users FOREIGN KEY(signed_off_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_reconciliation_runs_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_reconciliation_runs_organization_id ON reconciliation_runs (organization_id);

CREATE TABLE supplier_capabilities (
	supplier_account_id UUID NOT NULL, 
	airline_id UUID, 
	operation VARCHAR(32) NOT NULL, 
	mode VARCHAR(32) NOT NULL, 
	api_version VARCHAR(32), 
	verified_on DATE, 
	source_note VARCHAR(255), 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_supplier_capabilities PRIMARY KEY (id), 
	CONSTRAINT fk_supplier_capabilities_supplier_account_id_supplier_accounts FOREIGN KEY(supplier_account_id) REFERENCES supplier_accounts (id) ON DELETE CASCADE, 
	CONSTRAINT fk_supplier_capabilities_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE CASCADE, 
	CONSTRAINT ck_supplier_capabilities_supplierop CHECK (operation IN ('search', 'price', 'create_booking', 'retrieve', 'issue', 'void', 'cancel', 'refund_quote', 'refund_commit', 'change_quote', 'change_commit')), 
	CONSTRAINT ck_supplier_capabilities_capmode CHECK (mode IN ('supported', 'via_consolidator', 'manual', 'unsupported')), 
	CONSTRAINT fk_supplier_capabilities_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_supplier_capabilities_organization_id ON supplier_capabilities (organization_id);

CREATE UNIQUE INDEX uq_supplier_capabilities_key ON supplier_capabilities (supplier_account_id, operation, coalesce(airline_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE TABLE travellers (
	owner_user_id UUID NOT NULL, 
	pax_type VARCHAR(3) NOT NULL, 
	title VARCHAR(8), 
	first_name VARCHAR(80) NOT NULL, 
	last_name VARCHAR(80) NOT NULL, 
	date_of_birth DATE NOT NULL, 
	gender VARCHAR(1), 
	nationality VARCHAR(2), 
	passport_no_enc BYTEA, 
	passport_no_hash BYTEA, 
	passport_expiry DATE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_travellers PRIMARY KEY (id), 
	CONSTRAINT fk_travellers_owner_user_id_users FOREIGN KEY(owner_user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT fk_travellers_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_travellers_owner_user_id ON travellers (owner_user_id);

CREATE INDEX ix_travellers_organization_id ON travellers (organization_id);

CREATE TABLE user_org_roles (
	user_id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	role_id UUID NOT NULL, 
	granted_by UUID, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	CONSTRAINT pk_user_org_roles PRIMARY KEY (id), 
	CONSTRAINT uq_user_org_roles_user_id_organization_id_role_id UNIQUE (user_id, organization_id, role_id), 
	CONSTRAINT fk_user_org_roles_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	CONSTRAINT fk_user_org_roles_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE CASCADE, 
	CONSTRAINT fk_user_org_roles_role_id_roles FOREIGN KEY(role_id) REFERENCES roles (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_user_org_roles_granted_by_users FOREIGN KEY(granted_by) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX ix_user_org_roles_org ON user_org_roles (organization_id);

CREATE TABLE visa_applications (
	application_ref VARCHAR(20) NOT NULL, 
	applicant_name VARCHAR(160) NOT NULL, 
	passport_no_hash BYTEA, 
	destination_country VARCHAR(2) NOT NULL, 
	visa_type VARCHAR(24) NOT NULL, 
	stage VARCHAR(32) NOT NULL, 
	total_fee NUMERIC(12, 2) NOT NULL, 
	created_by UUID NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_visa_applications PRIMARY KEY (id), 
	CONSTRAINT uq_visa_applications_application_ref UNIQUE (application_ref), 
	CONSTRAINT ck_visa_applications_visastage CHECK (stage IN ('received', 'document_check', 'submitted_to_embassy', 'approved', 'delivered_to_agent')), 
	CONSTRAINT fk_visa_applications_created_by_users FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_visa_applications_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_visa_applications_organization_id ON visa_applications (organization_id);

CREATE INDEX ix_visa_applications_org_stage ON visa_applications (organization_id, stage);

CREATE TABLE wallets (
	owner_user_id UUID, 
	account_id UUID NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	balance NUMERIC(12, 2) NOT NULL, 
	credit_limit NUMERIC(12, 2) NOT NULL, 
	held_amount NUMERIC(12, 2) NOT NULL, 
	status VARCHAR(12) NOT NULL, 
	version_id INTEGER NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_wallets PRIMARY KEY (id), 
	CONSTRAINT ck_wallets_not_overdrawn CHECK (balance + credit_limit - held_amount >= 0), 
	CONSTRAINT ck_wallets_non_negative_parts CHECK (held_amount >= 0 AND credit_limit >= 0), 
	CONSTRAINT fk_wallets_owner_user_id_users FOREIGN KEY(owner_user_id) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_wallets_account_id_accounts FOREIGN KEY(account_id) REFERENCES accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_wallets_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_wallets_org_ccy ON wallets (organization_id, currency) WHERE owner_user_id IS NULL;

CREATE UNIQUE INDEX uq_wallets_owner_ccy ON wallets (organization_id, owner_user_id, currency) WHERE owner_user_id IS NOT NULL;

CREATE INDEX ix_wallets_organization_id ON wallets (organization_id);

CREATE TABLE booking_passengers (
	booking_id UUID NOT NULL, 
	traveller_id UUID, 
	pax_type VARCHAR(32) NOT NULL, 
	title VARCHAR(8), 
	first_name VARCHAR(80) NOT NULL, 
	last_name VARCHAR(80) NOT NULL, 
	date_of_birth DATE NOT NULL, 
	gender VARCHAR(1), 
	nationality VARCHAR(2), 
	passport_no_enc BYTEA, 
	passport_no_hash BYTEA, 
	passport_expiry DATE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_booking_passengers PRIMARY KEY (id), 
	CONSTRAINT fk_booking_passengers_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE CASCADE, 
	CONSTRAINT fk_booking_passengers_traveller_id_travellers FOREIGN KEY(traveller_id) REFERENCES travellers (id) ON DELETE SET NULL, 
	CONSTRAINT ck_booking_passengers_paxtype CHECK (pax_type IN ('adt', 'cnn', 'inf')), 
	CONSTRAINT fk_booking_passengers_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_booking_passengers_organization_id ON booking_passengers (organization_id);

CREATE INDEX ix_booking_passengers_booking_id ON booking_passengers (booking_id);

CREATE TABLE booking_status_history (
	id BIGSERIAL NOT NULL, 
	booking_id UUID NOT NULL, 
	from_status VARCHAR(32), 
	to_status VARCHAR(32) NOT NULL, 
	actor_user_id UUID, 
	reason VARCHAR(255), 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_booking_status_history PRIMARY KEY (id), 
	CONSTRAINT fk_booking_status_history_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE CASCADE, 
	CONSTRAINT fk_booking_status_history_actor_user_id_users FOREIGN KEY(actor_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_booking_status_history_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_booking_status_history_organization_id ON booking_status_history (organization_id);

CREATE INDEX ix_booking_status_history_booking ON booking_status_history (booking_id, id);

CREATE TABLE flight_segments (
	booking_id UUID NOT NULL, 
	direction VARCHAR(32) NOT NULL, 
	seq SMALLINT NOT NULL, 
	marketing_airline_id UUID NOT NULL, 
	operating_airline_id UUID, 
	flight_no VARCHAR(8) NOT NULL, 
	origin VARCHAR(3) NOT NULL, 
	destination VARCHAR(3) NOT NULL, 
	departs_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	arrives_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	dep_terminal VARCHAR(8), 
	arr_terminal VARCHAR(8), 
	cabin VARCHAR(16), 
	booking_class VARCHAR(2), 
	baggage_kg SMALLINT, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_flight_segments PRIMARY KEY (id), 
	CONSTRAINT uq_flight_segments_booking_id_direction_seq UNIQUE (booking_id, direction, seq), 
	CONSTRAINT fk_flight_segments_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE CASCADE, 
	CONSTRAINT ck_flight_segments_direction CHECK (direction IN ('out', 'ret', 'none')), 
	CONSTRAINT fk_flight_segments_marketing_airline_id_airlines FOREIGN KEY(marketing_airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_flight_segments_operating_airline_id_airlines FOREIGN KEY(operating_airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_flight_segments_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_flight_segments_organization_id ON flight_segments (organization_id);

CREATE INDEX ix_flight_segments_booking_id ON flight_segments (booking_id);

CREATE INDEX ix_flight_segments_dep ON flight_segments (origin, destination, departs_at);

CREATE TABLE payments (
	payer_user_id UUID, 
	booking_id UUID, 
	purpose VARCHAR(24) NOT NULL, 
	provider VARCHAR(32) NOT NULL, 
	provider_txn_id VARCHAR(96), 
	amount NUMERIC(12, 2) NOT NULL, 
	fee_amount NUMERIC(12, 2) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	idempotency_key VARCHAR(80) NOT NULL, 
	raw JSONB DEFAULT '{}'::jsonb NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_payments PRIMARY KEY (id), 
	CONSTRAINT ck_payments_positive CHECK (amount > 0), 
	CONSTRAINT uq_payments_organization_id_idempotency_key UNIQUE (organization_id, idempotency_key), 
	CONSTRAINT fk_payments_payer_user_id_users FOREIGN KEY(payer_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_payments_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_payments_payprovider CHECK (provider IN ('sslcommerz', 'bkash', 'nagad', 'stripe', 'paypal')), 
	CONSTRAINT ck_payments_paystatus CHECK (status IN ('initiated', 'authorized', 'captured', 'failed', 'refunded', 'expired')), 
	CONSTRAINT fk_payments_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_payments_org_status_created ON payments (organization_id, status, created_at);

CREATE INDEX ix_payments_organization_id ON payments (organization_id);

CREATE UNIQUE INDEX uq_payments_provider_txn ON payments (provider, provider_txn_id) WHERE provider_txn_id IS NOT NULL;

CREATE INDEX ix_payments_booking_id ON payments (booking_id);

CREATE TABLE price_quotes (
	booking_id UUID, 
	supplier_account_id UUID NOT NULL, 
	offer_ref VARCHAR(96) NOT NULL, 
	quote_ref VARCHAR(96), 
	currency VARCHAR(3) NOT NULL, 
	total_amount NUMERIC(12, 2) NOT NULL, 
	price_json JSONB NOT NULL, 
	fare_rules_hash VARCHAR(64), 
	fare_rules_ref VARCHAR(255), 
	price_changed BOOLEAN NOT NULL, 
	expires_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	accepted_by_user_id UUID, 
	accepted_at TIMESTAMP WITH TIME ZONE, 
	accepted_conditions_hash VARCHAR(64), 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_price_quotes PRIMARY KEY (id), 
	CONSTRAINT fk_price_quotes_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_price_quotes_supplier_account_id_supplier_accounts FOREIGN KEY(supplier_account_id) REFERENCES supplier_accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_price_quotes_accepted_by_user_id_users FOREIGN KEY(accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_price_quotes_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_price_quotes_organization_id ON price_quotes (organization_id);

CREATE INDEX ix_price_quotes_booking ON price_quotes (booking_id, created_at);

CREATE INDEX ix_price_quotes_offer_ref ON price_quotes (offer_ref);

CREATE TABLE supplier_attempts (
	booking_id UUID, 
	supplier_account_id UUID NOT NULL, 
	operation VARCHAR(32) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	idempotency_key VARCHAR(96) NOT NULL, 
	correlation_id VARCHAR(48) NOT NULL, 
	supplier_txn_id VARCHAR(96), 
	provider_ref VARCHAR(64), 
	error_code VARCHAR(64), 
	raw_payload_ref VARCHAR(255), 
	started_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	finished_at TIMESTAMP WITH TIME ZONE, 
	resolved_by UUID, 
	resolved_at TIMESTAMP WITH TIME ZONE, 
	resolution_note VARCHAR(255), 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_supplier_attempts PRIMARY KEY (id), 
	CONSTRAINT uq_supplier_attempts_booking_id_operation_idempotency_key UNIQUE (booking_id, operation, idempotency_key), 
	CONSTRAINT fk_supplier_attempts_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_supplier_attempts_supplier_account_id_supplier_accounts FOREIGN KEY(supplier_account_id) REFERENCES supplier_accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_supplier_attempts_supplierop CHECK (operation IN ('search', 'price', 'create_booking', 'retrieve', 'issue', 'void', 'cancel', 'refund_quote', 'refund_commit', 'change_quote', 'change_commit')), 
	CONSTRAINT ck_supplier_attempts_attemptstatus CHECK (status IN ('success', 'business_rejected', 'retryable_failure', 'unknown')), 
	CONSTRAINT fk_supplier_attempts_resolved_by_users FOREIGN KEY(resolved_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_supplier_attempts_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_supplier_attempts_unknown ON supplier_attempts (started_at) WHERE status = 'unknown' AND resolved_at IS NULL;

CREATE INDEX ix_supplier_attempts_booking ON supplier_attempts (booking_id, started_at);

CREATE INDEX ix_supplier_attempts_organization_id ON supplier_attempts (organization_id);

CREATE TABLE visa_events (
	id BIGSERIAL NOT NULL, 
	application_id UUID NOT NULL, 
	stage VARCHAR(32) NOT NULL, 
	note VARCHAR(255), 
	actor_user_id UUID, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_visa_events PRIMARY KEY (id), 
	CONSTRAINT fk_visa_events_application_id_visa_applications FOREIGN KEY(application_id) REFERENCES visa_applications (id) ON DELETE CASCADE, 
	CONSTRAINT ck_visa_events_visastage CHECK (stage IN ('received', 'document_check', 'submitted_to_embassy', 'approved', 'delivered_to_agent')), 
	CONSTRAINT fk_visa_events_actor_user_id_users FOREIGN KEY(actor_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_visa_events_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_visa_events_organization_id ON visa_events (organization_id);

CREATE INDEX ix_visa_events_application ON visa_events (application_id, id);

CREATE TABLE wallet_holds (
	wallet_id UUID NOT NULL, 
	booking_id UUID, 
	amount NUMERIC(12, 2) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	expires_at TIMESTAMP WITH TIME ZONE, 
	idempotency_key VARCHAR(80), 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_wallet_holds PRIMARY KEY (id), 
	CONSTRAINT ck_wallet_holds_positive CHECK (amount > 0), 
	CONSTRAINT fk_wallet_holds_wallet_id_wallets FOREIGN KEY(wallet_id) REFERENCES wallets (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_wallet_holds_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_wallet_holds_holdstatus CHECK (status IN ('active', 'captured', 'released', 'expired')), 
	CONSTRAINT fk_wallet_holds_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_wallet_holds_wallet_id ON wallet_holds (wallet_id);

CREATE UNIQUE INDEX uq_wallet_holds_org_idem ON wallet_holds (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE INDEX ix_wallet_holds_active_expiry ON wallet_holds (status, expires_at);

CREATE INDEX ix_wallet_holds_organization_id ON wallet_holds (organization_id);

CREATE TABLE booking_price_lines (
	booking_id UUID NOT NULL, 
	passenger_id UUID, 
	component VARCHAR(32) NOT NULL, 
	label VARCHAR(40), 
	amount NUMERIC(12, 2) NOT NULL, 
	refundable BOOLEAN NOT NULL, 
	rule_type VARCHAR(24), 
	rule_id UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_booking_price_lines PRIMARY KEY (id), 
	CONSTRAINT fk_booking_price_lines_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE CASCADE, 
	CONSTRAINT fk_booking_price_lines_passenger_id_booking_passengers FOREIGN KEY(passenger_id) REFERENCES booking_passengers (id) ON DELETE CASCADE, 
	CONSTRAINT ck_booking_price_lines_pricecomponent CHECK (component IN ('base', 'commission', 'tax', 'ait', 'markup', 'service_fee', 'discount', 'supplier_cost')), 
	CONSTRAINT fk_booking_price_lines_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_booking_price_lines_organization_id ON booking_price_lines (organization_id);

CREATE INDEX ix_booking_price_lines_booking_id ON booking_price_lines (booking_id);

CREATE TABLE journal_entries (
	txn_ref VARCHAR(32) NOT NULL, 
	kind VARCHAR(32) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	booking_id UUID, 
	payment_id UUID, 
	reversal_of_id UUID, 
	idempotency_key VARCHAR(80), 
	memo VARCHAR(255), 
	created_by UUID, 
	posted_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_journal_entries PRIMARY KEY (id), 
	CONSTRAINT uq_journal_entries_txn_ref UNIQUE (txn_ref), 
	CONSTRAINT ck_journal_entries_journalkind CHECK (kind IN ('deposit', 'sale', 'partial_payment', 'refund', 'void', 'reissue', 'markup_adj', 'stage_fee', 'commission', 'manual', 'reversal', 'supplier_settlement')), 
	CONSTRAINT ck_journal_entries_journalstatus CHECK (status IN ('posted', 'reversed')), 
	CONSTRAINT fk_journal_entries_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_journal_entries_payment_id_payments FOREIGN KEY(payment_id) REFERENCES payments (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_journal_entries_reversal_of_id_journal_entries FOREIGN KEY(reversal_of_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_journal_entries_created_by_users FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_journal_entries_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_journal_entries_org_idem ON journal_entries (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE INDEX ix_journal_entries_organization_id ON journal_entries (organization_id);

CREATE INDEX ix_journal_entries_org_posted ON journal_entries (organization_id, posted_at);

CREATE INDEX ix_journal_entries_booking_id ON journal_entries (booking_id);

CREATE TABLE payment_disputes (
	payment_id UUID NOT NULL, 
	provider_case_id VARCHAR(96) NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	evidence_due_at TIMESTAMP WITH TIME ZONE, 
	evidence_ref VARCHAR(255), 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_payment_disputes PRIMARY KEY (id), 
	CONSTRAINT uq_payment_disputes_payment_id_provider_case_id UNIQUE (payment_id, provider_case_id), 
	CONSTRAINT fk_payment_disputes_payment_id_payments FOREIGN KEY(payment_id) REFERENCES payments (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_payment_disputes_disputestatus CHECK (status IN ('open', 'evidence_submitted', 'won', 'lost')), 
	CONSTRAINT fk_payment_disputes_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_payment_disputes_organization_id ON payment_disputes (organization_id);

CREATE TABLE reconciliation_items (
	run_id UUID, 
	queue VARCHAR(32) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	severity VARCHAR(8) NOT NULL, 
	booking_id UUID, 
	payment_id UUID, 
	external_ref VARCHAR(96), 
	amount_at_risk NUMERIC(12, 2) NOT NULL, 
	owner_user_id UUID, 
	resolution TEXT, 
	evidence_ref VARCHAR(255), 
	resolved_at TIMESTAMP WITH TIME ZONE, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_reconciliation_items PRIMARY KEY (id), 
	CONSTRAINT fk_reconciliation_items_run_id_reconciliation_runs FOREIGN KEY(run_id) REFERENCES reconciliation_runs (id) ON DELETE SET NULL, 
	CONSTRAINT ck_reconciliation_items_reconqueue CHECK (queue IN ('booking_unknown', 'ticket_not_issued', 'payment_authorized_not_captured', 'captured_no_booking', 'booked_no_payment', 'duplicate_booking', 'duplicate_capture', 'refund_overdue', 'supplier_amount_mismatch', 'currency_or_tax_variance', 'adm_acm_review')), 
	CONSTRAINT ck_reconciliation_items_reconstatus CHECK (status IN ('open', 'assigned', 'resolved', 'written_off')), 
	CONSTRAINT fk_reconciliation_items_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_reconciliation_items_payment_id_payments FOREIGN KEY(payment_id) REFERENCES payments (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_reconciliation_items_owner_user_id_users FOREIGN KEY(owner_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_reconciliation_items_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_reconciliation_items_organization_id ON reconciliation_items (organization_id);

CREATE INDEX ix_reconciliation_items_booking ON reconciliation_items (booking_id);

CREATE INDEX ix_reconciliation_items_open ON reconciliation_items (organization_id, queue, created_at) WHERE status IN ('open','assigned');

CREATE TABLE tickets (
	booking_id UUID NOT NULL, 
	passenger_id UUID NOT NULL, 
	airline_id UUID NOT NULL, 
	ticket_number VARCHAR(16) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	issued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_tickets PRIMARY KEY (id), 
	CONSTRAINT fk_tickets_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE CASCADE, 
	CONSTRAINT fk_tickets_passenger_id_booking_passengers FOREIGN KEY(passenger_id) REFERENCES booking_passengers (id) ON DELETE CASCADE, 
	CONSTRAINT fk_tickets_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT uq_tickets_ticket_number UNIQUE (ticket_number), 
	CONSTRAINT ck_tickets_ticketstatus CHECK (status IN ('open', 'used', 'void', 'refunded', 'exchanged')), 
	CONSTRAINT fk_tickets_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_tickets_organization_id ON tickets (organization_id);

CREATE INDEX ix_tickets_booking_id ON tickets (booking_id);

CREATE TABLE adm_acm_cases (
	kind VARCHAR(32) NOT NULL, 
	memo_no VARCHAR(40) NOT NULL, 
	airline_id UUID NOT NULL, 
	market VARCHAR(2) NOT NULL, 
	booking_id UUID, 
	ticket_number VARCHAR(16), 
	reason_code VARCHAR(32), 
	allegation TEXT, 
	amount NUMERIC(12, 2) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	issued_on DATE NOT NULL, 
	deadline_at TIMESTAMP WITH TIME ZONE, 
	deadline_source VARCHAR(255), 
	status VARCHAR(32) NOT NULL, 
	owner_user_id UUID, 
	agency_position TEXT, 
	accepted_amount NUMERIC(12, 2), 
	evidence_index JSONB DEFAULT '{}'::jsonb NOT NULL, 
	journal_id UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_adm_acm_cases PRIMARY KEY (id), 
	CONSTRAINT uq_adm_acm_cases_organization_id_airline_id_memo_no UNIQUE (organization_id, airline_id, memo_no), 
	CONSTRAINT ck_adm_acm_cases_deadline_needs_source CHECK (deadline_at IS NULL OR deadline_source IS NOT NULL), 
	CONSTRAINT ck_adm_acm_cases_memokind CHECK (kind IN ('adm', 'acm')), 
	CONSTRAINT fk_adm_acm_cases_airline_id_airlines FOREIGN KEY(airline_id) REFERENCES airlines (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_adm_acm_cases_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_adm_acm_cases_memostatus CHECK (status IN ('registered', 'under_review', 'accepted', 'partially_accepted', 'disputed', 'escalated', 'closed')), 
	CONSTRAINT fk_adm_acm_cases_owner_user_id_users FOREIGN KEY(owner_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_adm_acm_cases_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_adm_acm_cases_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_adm_acm_cases_open_deadline ON adm_acm_cases (deadline_at) WHERE status NOT IN ('accepted','closed');

CREATE INDEX ix_adm_acm_cases_organization_id ON adm_acm_cases (organization_id);

CREATE TABLE after_sales_requests (
	booking_id UUID NOT NULL, 
	request_type VARCHAR(32) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	serial_no VARCHAR(32) NOT NULL, 
	rejection_serial VARCHAR(32), 
	requested_by UUID NOT NULL, 
	reason TEXT, 
	new_departs_at TIMESTAMP WITH TIME ZONE, 
	new_schedule_note TEXT, 
	quote_total NUMERIC(12, 2), 
	quote_expires_at TIMESTAMP WITH TIME ZONE, 
	quoted_by UUID, 
	decided_at TIMESTAMP WITH TIME ZONE, 
	resulting_booking_id UUID, 
	journal_id UUID, 
	idempotency_key VARCHAR(80) NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_after_sales_requests PRIMARY KEY (id), 
	CONSTRAINT uq_after_sales_requests_organization_id_idempotency_key UNIQUE (organization_id, idempotency_key), 
	CONSTRAINT fk_after_sales_requests_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_after_sales_requests_aftersalestype CHECK (request_type IN ('void', 'refund', 'reissue')), 
	CONSTRAINT ck_after_sales_requests_aftersalesstatus CHECK (status IN ('requested', 'quotation_sent', 'quotation_expired', 'quotation_rejected', 'quotation_approved', 'in_process', 'request_approved', 'rejected', 'completed')), 
	CONSTRAINT uq_after_sales_requests_serial_no UNIQUE (serial_no), 
	CONSTRAINT uq_after_sales_requests_rejection_serial UNIQUE (rejection_serial), 
	CONSTRAINT fk_after_sales_requests_requested_by_users FOREIGN KEY(requested_by) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_after_sales_requests_quoted_by_users FOREIGN KEY(quoted_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_after_sales_requests_resulting_booking_id_bookings FOREIGN KEY(resulting_booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_after_sales_requests_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_after_sales_requests_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_after_sales_org_type_status ON after_sales_requests (organization_id, request_type, status);

CREATE INDEX ix_after_sales_requests_organization_id ON after_sales_requests (organization_id);

CREATE INDEX ix_after_sales_quote_expiry ON after_sales_requests (quote_expires_at) WHERE status = 'quotation_sent';

CREATE INDEX ix_after_sales_booking ON after_sales_requests (booking_id);

CREATE TABLE deposit_requests (
	wallet_id UUID NOT NULL, 
	requested_by UUID NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	method VARCHAR(32) NOT NULL, 
	reference_no VARCHAR(64) NOT NULL, 
	proof_storage_key VARCHAR(255), 
	status VARCHAR(32) NOT NULL, 
	reviewed_by UUID, 
	reviewed_at TIMESTAMP WITH TIME ZONE, 
	journal_id UUID, 
	note VARCHAR(255), 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_deposit_requests PRIMARY KEY (id), 
	CONSTRAINT ck_deposit_requests_positive CHECK (amount > 0), 
	CONSTRAINT uq_deposit_requests_method_reference_no UNIQUE (method, reference_no), 
	CONSTRAINT fk_deposit_requests_wallet_id_wallets FOREIGN KEY(wallet_id) REFERENCES wallets (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_deposit_requests_requested_by_users FOREIGN KEY(requested_by) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_deposit_requests_paymethod CHECK (method IN ('bank', 'bkash', 'nagad', 'rocket', 'card', 'intl_gateway', 'wallet')), 
	CONSTRAINT ck_deposit_requests_approvalstatus CHECK (status IN ('pending', 'approved', 'rejected')), 
	CONSTRAINT fk_deposit_requests_reviewed_by_users FOREIGN KEY(reviewed_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_deposit_requests_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_deposit_requests_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_deposit_requests_organization_id ON deposit_requests (organization_id);

CREATE INDEX ix_deposit_requests_org_status ON deposit_requests (organization_id, status, created_at);

CREATE TABLE invoices (
	invoice_no VARCHAR(32) NOT NULL, 
	customer_org_id UUID, 
	customer_user_id UUID, 
	booking_id UUID, 
	journal_id UUID, 
	status VARCHAR(32) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	subtotal NUMERIC(12, 2) NOT NULL, 
	tax_total NUMERIC(12, 2) NOT NULL, 
	total NUMERIC(12, 2) NOT NULL, 
	issue_date DATE NOT NULL, 
	due_date DATE, 
	pdf_storage_key VARCHAR(255), 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_invoices PRIMARY KEY (id), 
	CONSTRAINT uq_invoices_organization_id_invoice_no UNIQUE (organization_id, invoice_no), 
	CONSTRAINT fk_invoices_customer_org_id_organizations FOREIGN KEY(customer_org_id) REFERENCES organizations (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_invoices_customer_user_id_users FOREIGN KEY(customer_user_id) REFERENCES users (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_invoices_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_invoices_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_invoices_invoicestatus CHECK (status IN ('draft', 'issued', 'paid', 'void')), 
	CONSTRAINT fk_invoices_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_invoices_booking_id ON invoices (booking_id);

CREATE INDEX ix_invoices_organization_id ON invoices (organization_id);

CREATE INDEX ix_invoices_org_issue ON invoices (organization_id, issue_date);

CREATE TABLE ledger_entries (
	id BIGSERIAL NOT NULL, 
	journal_id UUID NOT NULL, 
	account_id UUID NOT NULL, 
	wallet_id UUID, 
	debit NUMERIC(12, 2) NOT NULL, 
	credit NUMERIC(12, 2) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	balance_after NUMERIC(12, 2), 
	counterparty_org_id UUID, 
	agent_user_id UUID, 
	payment_method VARCHAR(32), 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_ledger_entries PRIMARY KEY (id), 
	CONSTRAINT ck_ledger_entries_one_sided_positive CHECK (debit >= 0 AND credit >= 0 AND (debit = 0 OR credit = 0) AND (debit + credit) > 0), 
	CONSTRAINT fk_ledger_entries_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_ledger_entries_account_id_accounts FOREIGN KEY(account_id) REFERENCES accounts (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_ledger_entries_wallet_id_wallets FOREIGN KEY(wallet_id) REFERENCES wallets (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_ledger_entries_counterparty_org_id_organizations FOREIGN KEY(counterparty_org_id) REFERENCES organizations (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_ledger_entries_agent_user_id_users FOREIGN KEY(agent_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT ck_ledger_entries_paymethod CHECK (payment_method IN ('bank', 'bkash', 'nagad', 'rocket', 'card', 'intl_gateway', 'wallet')), 
	CONSTRAINT fk_ledger_entries_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_ledger_entries_journal_id ON ledger_entries (journal_id);

CREATE INDEX ix_ledger_entries_org_created ON ledger_entries (organization_id, created_at);

CREATE INDEX ix_ledger_entries_organization_id ON ledger_entries (organization_id);

CREATE INDEX ix_ledger_entries_account_id_id ON ledger_entries (account_id, id);

CREATE INDEX ix_ledger_entries_wallet_id_id ON ledger_entries (wallet_id, id);

CREATE TABLE partial_payment_plans (
	booking_id UUID NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	approved_amount NUMERIC(12, 2), 
	settlement_due_at TIMESTAMP WITH TIME ZONE, 
	on_default VARCHAR(32) NOT NULL, 
	approved_by UUID, 
	journal_id UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_partial_payment_plans PRIMARY KEY (id), 
	CONSTRAINT uq_partial_payment_plans_booking_id UNIQUE (booking_id), 
	CONSTRAINT fk_partial_payment_plans_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_partial_payment_plans_planstatus CHECK (status IN ('requested', 'approved', 'settled', 'defaulted', 'cancelled')), 
	CONSTRAINT ck_partial_payment_plans_ondefault CHECK (on_default IN ('auto_cancel', 'flag_admin')), 
	CONSTRAINT fk_partial_payment_plans_approved_by_users FOREIGN KEY(approved_by) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_partial_payment_plans_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_partial_payment_plans_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_partial_payment_plans_organization_id ON partial_payment_plans (organization_id);

CREATE INDEX ix_partial_payment_plans_due ON partial_payment_plans (status, settlement_due_at);

CREATE TABLE payment_refunds (
	payment_id UUID NOT NULL, 
	booking_id UUID, 
	amount NUMERIC(12, 2) NOT NULL, 
	currency VARCHAR(3) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	provider_refund_id VARCHAR(96), 
	reason VARCHAR(255), 
	due_at TIMESTAMP WITH TIME ZONE, 
	journal_id UUID, 
	idempotency_key VARCHAR(80) NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
	CONSTRAINT pk_payment_refunds PRIMARY KEY (id), 
	CONSTRAINT ck_payment_refunds_positive CHECK (amount > 0), 
	CONSTRAINT uq_payment_refunds_organization_id_idempotency_key UNIQUE (organization_id, idempotency_key), 
	CONSTRAINT fk_payment_refunds_payment_id_payments FOREIGN KEY(payment_id) REFERENCES payments (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_payment_refunds_booking_id_bookings FOREIGN KEY(booking_id) REFERENCES bookings (id) ON DELETE RESTRICT, 
	CONSTRAINT ck_payment_refunds_refundstatus CHECK (status IN ('pending', 'completed', 'failed')), 
	CONSTRAINT fk_payment_refunds_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_payment_refunds_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_payment_refunds_pending_due ON payment_refunds (due_at) WHERE status = 'pending';

CREATE INDEX ix_payment_refunds_organization_id ON payment_refunds (organization_id);

CREATE UNIQUE INDEX uq_payment_refunds_provider ON payment_refunds (payment_id, provider_refund_id) WHERE provider_refund_id IS NOT NULL;

CREATE TABLE visa_stage_payments (
	application_id UUID NOT NULL, 
	stage VARCHAR(32) NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	settled_at TIMESTAMP WITH TIME ZONE, 
	journal_id UUID, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_visa_stage_payments PRIMARY KEY (id), 
	CONSTRAINT uq_visa_stage_payments_application_id_stage UNIQUE (application_id, stage), 
	CONSTRAINT fk_visa_stage_payments_application_id_visa_applications FOREIGN KEY(application_id) REFERENCES visa_applications (id) ON DELETE CASCADE, 
	CONSTRAINT ck_visa_stage_payments_visastage CHECK (stage IN ('received', 'document_check', 'submitted_to_embassy', 'approved', 'delivered_to_agent')), 
	CONSTRAINT fk_visa_stage_payments_journal_id_journal_entries FOREIGN KEY(journal_id) REFERENCES journal_entries (id) ON DELETE RESTRICT, 
	CONSTRAINT fk_visa_stage_payments_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_visa_stage_payments_organization_id ON visa_stage_payments (organization_id);

CREATE TABLE after_sales_quote_lines (
	request_id UUID NOT NULL, 
	component VARCHAR(32) NOT NULL, 
	old_amount NUMERIC(12, 2), 
	new_amount NUMERIC(12, 2), 
	amount NUMERIC(12, 2) NOT NULL, 
	refundable BOOLEAN NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_after_sales_quote_lines PRIMARY KEY (id), 
	CONSTRAINT fk_after_sales_quote_lines_request_id_after_sales_requests FOREIGN KEY(request_id) REFERENCES after_sales_requests (id) ON DELETE CASCADE, 
	CONSTRAINT ck_after_sales_quote_lines_quotecomponent CHECK (component IN ('fare_diff', 'tax_diff', 'airline_charge', 'service_charge', 'ait_non_refundable', 'refund_amount')), 
	CONSTRAINT fk_after_sales_quote_lines_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_after_sales_quote_lines_organization_id ON after_sales_quote_lines (organization_id);

CREATE INDEX ix_after_sales_quote_lines_request_id ON after_sales_quote_lines (request_id);

CREATE TABLE invoice_lines (
	invoice_id UUID NOT NULL, 
	description VARCHAR(255) NOT NULL, 
	component VARCHAR(24), 
	quantity INTEGER NOT NULL, 
	unit_price NUMERIC(12, 2) NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	id UUID NOT NULL, 
	organization_id UUID NOT NULL, 
	CONSTRAINT pk_invoice_lines PRIMARY KEY (id), 
	CONSTRAINT fk_invoice_lines_invoice_id_invoices FOREIGN KEY(invoice_id) REFERENCES invoices (id) ON DELETE CASCADE, 
	CONSTRAINT fk_invoice_lines_organization_id_organizations FOREIGN KEY(organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);

CREATE INDEX ix_invoice_lines_invoice_id ON invoice_lines (invoice_id);

CREATE INDEX ix_invoice_lines_organization_id ON invoice_lines (organization_id);
