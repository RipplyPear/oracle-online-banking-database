WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

CREATE TABLE customers (
    customer_id     VARCHAR2(16 CHAR),
    first_name      VARCHAR2(50 CHAR)    NOT NULL,
    last_name       VARCHAR2(50 CHAR)    NOT NULL,
    email           VARCHAR2(254 CHAR)   NOT NULL,
    phone_number    VARCHAR2(20 CHAR)    NOT NULL,
    address         VARCHAR2(200 CHAR)   NOT NULL,
    date_of_birth   DATE                 NOT NULL,
    registered_at   DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT uq_customers_phone UNIQUE (phone_number),
    CONSTRAINT ck_customers_email
        CHECK (REGEXP_LIKE(email, '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$')),
    CONSTRAINT ck_customers_dates
        CHECK (date_of_birth < registered_at)
);

CREATE TABLE accounts (
    iban                VARCHAR2(34 CHAR),
    account_type        VARCHAR2(16 CHAR)    NOT NULL,
    status              VARCHAR2(16 CHAR)    DEFAULT 'ACTIVE' NOT NULL,
    available_balance   NUMBER(18, 2)        DEFAULT 0 NOT NULL,
    currency_code       CHAR(3 CHAR)         NOT NULL,
    bic                 VARCHAR2(11 CHAR)    NOT NULL,
    opened_at           DATE DEFAULT SYSDATE NOT NULL,
    closed_at           DATE,
    customer_id         VARCHAR2(16 CHAR)    NOT NULL,
    CONSTRAINT pk_accounts PRIMARY KEY (iban),
    CONSTRAINT fk_accounts_customers
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    CONSTRAINT ck_accounts_iban
        CHECK (REGEXP_LIKE(iban, '^[A-Z0-9]{15,34}$')),
    CONSTRAINT ck_accounts_type
        CHECK (account_type IN ('CHECKING', 'SAVINGS')),
    CONSTRAINT ck_accounts_status
        CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED')),
    CONSTRAINT ck_accounts_balance
        CHECK (available_balance >= 0),
    CONSTRAINT ck_accounts_currency
        CHECK (REGEXP_LIKE(currency_code, '^[A-Z]{3}$')),
    CONSTRAINT ck_accounts_bic
        CHECK (REGEXP_LIKE(bic, '^[A-Z0-9]{8}([A-Z0-9]{3})?$')),
    CONSTRAINT ck_accounts_closure
        CHECK (
            (status = 'CLOSED' AND closed_at IS NOT NULL
                AND closed_at >= opened_at)
            OR
            (status <> 'CLOSED' AND closed_at IS NULL)
        )
);

CREATE INDEX ix_accounts_customer_id ON accounts (customer_id);

CREATE TABLE external_payees (
    iban        VARCHAR2(34 CHAR),
    payee_name  VARCHAR2(100 CHAR) NOT NULL,
    bic         VARCHAR2(11 CHAR)  NOT NULL,
    CONSTRAINT pk_external_payees PRIMARY KEY (iban),
    CONSTRAINT ck_external_payees_iban
        CHECK (REGEXP_LIKE(iban, '^[A-Z0-9]{15,34}$')),
    CONSTRAINT ck_external_payees_bic
        CHECK (REGEXP_LIKE(bic, '^[A-Z0-9]{8}([A-Z0-9]{3})?$'))
);

CREATE TABLE transfers (
    transfer_id                VARCHAR2(32 CHAR),
    transfer_type              VARCHAR2(8 CHAR)   NOT NULL,
    transferred_at             TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    status                     VARCHAR2(16 CHAR)  DEFAULT 'PENDING' NOT NULL,
    description                VARCHAR2(250 CHAR),
    original_amount            NUMBER(18, 2)      NOT NULL,
    original_currency          CHAR(3 CHAR)       NOT NULL,
    converted_amount           NUMBER(18, 2)      NOT NULL,
    target_currency            CHAR(3 CHAR)       NOT NULL,
    exchange_rate              NUMBER(18, 8)      DEFAULT 1 NOT NULL,
    fee_amount                 NUMBER(18, 2)      DEFAULT 0 NOT NULL,
    total_amount               NUMBER(18, 2)      NOT NULL,
    source_iban                VARCHAR2(34 CHAR)  NOT NULL,
    destination_account_iban   VARCHAR2(34 CHAR),
    destination_payee_iban     VARCHAR2(34 CHAR),
    CONSTRAINT pk_transfers PRIMARY KEY (transfer_id),
    CONSTRAINT fk_transfers_source
        FOREIGN KEY (source_iban) REFERENCES accounts (iban),
    CONSTRAINT fk_transfers_destination_account
        FOREIGN KEY (destination_account_iban) REFERENCES accounts (iban),
    CONSTRAINT fk_transfers_destination_payee
        FOREIGN KEY (destination_payee_iban) REFERENCES external_payees (iban),
    CONSTRAINT ck_transfers_type
        CHECK (transfer_type IN ('INTERNAL', 'EXTERNAL')),
    CONSTRAINT ck_transfers_status
        CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'DECLINED', 'CANCELLED')),
    CONSTRAINT ck_transfers_amounts
        CHECK (
            original_amount > 0
            AND converted_amount > 0
            AND exchange_rate > 0
            AND fee_amount >= 0
            AND total_amount >= 0
        ),
    CONSTRAINT ck_transfers_currencies
        CHECK (
            REGEXP_LIKE(original_currency, '^[A-Z]{3}$')
            AND REGEXP_LIKE(target_currency, '^[A-Z]{3}$')
        ),
    CONSTRAINT ck_transfers_destination
        CHECK (
            (transfer_type = 'INTERNAL'
                AND destination_account_iban IS NOT NULL
                AND destination_payee_iban IS NULL)
            OR
            (transfer_type = 'EXTERNAL'
                AND destination_account_iban IS NULL
                AND destination_payee_iban IS NOT NULL)
        ),
    CONSTRAINT ck_transfers_distinct_accounts
        CHECK (
            destination_account_iban IS NULL
            OR source_iban <> destination_account_iban
        )
);

CREATE INDEX ix_transfers_source
    ON transfers (source_iban);
CREATE INDEX ix_transfers_destination_account
    ON transfers (destination_account_iban);
CREATE INDEX ix_transfers_destination_payee
    ON transfers (destination_payee_iban);
CREATE INDEX ix_transfers_date
    ON transfers (transferred_at);

CREATE TABLE transactions (
    transaction_id      VARCHAR2(32 CHAR),
    merchant_name       VARCHAR2(100 CHAR) NOT NULL,
    category            VARCHAR2(50 CHAR)  NOT NULL,
    transacted_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    status              VARCHAR2(16 CHAR)  DEFAULT 'PENDING' NOT NULL,
    description         VARCHAR2(250 CHAR),
    original_amount     NUMBER(18, 2)      NOT NULL,
    original_currency   CHAR(3 CHAR)       NOT NULL,
    converted_amount    NUMBER(18, 2)      NOT NULL,
    target_currency     CHAR(3 CHAR)       NOT NULL,
    exchange_rate       NUMBER(18, 8)      DEFAULT 1 NOT NULL,
    fee_amount          NUMBER(18, 2)      DEFAULT 0 NOT NULL,
    total_amount        NUMBER(18, 2)      NOT NULL,
    account_iban        VARCHAR2(34 CHAR)  NOT NULL,
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transactions_accounts
        FOREIGN KEY (account_iban) REFERENCES accounts (iban),
    CONSTRAINT ck_transactions_status
        CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'DECLINED', 'CANCELLED')),
    CONSTRAINT ck_transactions_amounts
        CHECK (
            original_amount > 0
            AND converted_amount > 0
            AND exchange_rate > 0
            AND fee_amount >= 0
            AND total_amount >= 0
        ),
    CONSTRAINT ck_transactions_currencies
        CHECK (
            REGEXP_LIKE(original_currency, '^[A-Z]{3}$')
            AND REGEXP_LIKE(target_currency, '^[A-Z]{3}$')
        )
);

CREATE INDEX ix_transactions_account ON transactions (account_iban);
CREATE INDEX ix_transactions_date ON transactions (transacted_at);
CREATE INDEX ix_transactions_category ON transactions (category);

CREATE SEQUENCE seq_transfers START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_transactions START WITH 1000 INCREMENT BY 1 NOCACHE;

PROMPT BANKING_APP schema created successfully.