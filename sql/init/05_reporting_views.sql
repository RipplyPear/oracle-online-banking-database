WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

CREATE OR REPLACE VIEW v_customer_balance_summary AS
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    a.currency_code,
    COUNT(a.iban) AS account_count,
    SUM(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE 0 END) AS active_account_count,
    SUM(a.available_balance) AS total_available_balance
FROM customers c
JOIN accounts a ON a.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name,
    a.currency_code;

CREATE OR REPLACE VIEW v_transfer_details AS
SELECT
    t.transfer_id,
    t.transferred_at,
    t.transfer_type,
    t.status,
    t.description,
    t.source_iban,
    source_customer.customer_id AS source_customer_id,
    source_customer.first_name || ' ' || source_customer.last_name AS source_customer_name,
    CASE
        WHEN t.transfer_type = 'INTERNAL' THEN t.destination_account_iban
        ELSE t.destination_payee_iban
    END AS destination_iban,
    CASE
        WHEN t.transfer_type = 'INTERNAL'
            THEN destination_customer.first_name || ' ' || destination_customer.last_name
        ELSE payee.payee_name
    END AS destination_name,
    t.original_amount,
    t.original_currency,
    t.converted_amount,
    t.target_currency,
    t.exchange_rate,
    t.fee_amount,
    t.total_amount
FROM transfers t
JOIN accounts source_account
  ON source_account.iban = t.source_iban
JOIN customers source_customer
  ON source_customer.customer_id = source_account.customer_id
LEFT JOIN accounts destination_account
  ON destination_account.iban = t.destination_account_iban
LEFT JOIN customers destination_customer
  ON destination_customer.customer_id = destination_account.customer_id
LEFT JOIN external_payees payee
  ON payee.iban = t.destination_payee_iban;

CREATE OR REPLACE VIEW v_monthly_customer_outflow AS
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    TRUNC(t.transferred_at, 'MM') AS activity_month,
    t.original_currency AS currency_code,
    COUNT(*) AS transfer_count,
    SUM(t.original_amount) AS transferred_amount,
    SUM(t.fee_amount) AS fee_amount,
    SUM(t.total_amount) AS total_debited
FROM transfers t
JOIN accounts a ON a.iban = t.source_iban
JOIN customers c ON c.customer_id = a.customer_id
WHERE t.status = 'COMPLETED'
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name,
    TRUNC(t.transferred_at, 'MM'),
    t.original_currency;

CREATE OR REPLACE VIEW v_account_activity AS
SELECT
    t.transferred_at AS activity_at,
    'TRANSFER' AS activity_type,
    'OUTGOING' AS direction,
    t.transfer_id AS reference_id,
    t.source_iban AS account_iban,
    CASE
        WHEN t.transfer_type = 'INTERNAL' THEN t.destination_account_iban
        ELSE t.destination_payee_iban
    END AS counterparty,
    t.status,
    t.original_amount AS amount,
    t.original_currency AS currency_code,
    t.fee_amount
FROM transfers t
UNION ALL
SELECT
    t.transferred_at AS activity_at,
    'TRANSFER' AS activity_type,
    'INCOMING' AS direction,
    t.transfer_id AS reference_id,
    t.destination_account_iban AS account_iban,
    t.source_iban AS counterparty,
    t.status,
    t.converted_amount AS amount,
    t.target_currency AS currency_code,
    CAST(0 AS NUMBER(18, 2)) AS fee_amount
FROM transfers t
WHERE t.transfer_type = 'INTERNAL'
UNION ALL
SELECT
    tx.transacted_at AS activity_at,
    'TRANSACTION' AS activity_type,
    'OUTGOING' AS direction,
    tx.transaction_id AS reference_id,
    tx.account_iban,
    tx.merchant_name AS counterparty,
    tx.status,
    tx.original_amount AS amount,
    tx.original_currency AS currency_code,
    tx.fee_amount
FROM transactions tx;

SHOW ERRORS VIEW v_customer_balance_summary
SHOW ERRORS VIEW v_transfer_details
SHOW ERRORS VIEW v_monthly_customer_outflow
SHOW ERRORS VIEW v_account_activity

PROMPT Reporting views created successfully.
