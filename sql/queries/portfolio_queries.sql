WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 100
SET LINESIZE 220
SET FEEDBACK ON
SET NULL "(null)"

PROMPT 1. Customer balances by currency
SELECT
    customer_id,
    customer_name,
    currency_code,
    account_count,
    total_available_balance
FROM v_customer_balance_summary
ORDER BY customer_name, currency_code;

PROMPT 2. Balance ranking within each currency
SELECT
    customer_name,
    currency_code,
    total_available_balance,
    DENSE_RANK() OVER (
        PARTITION BY currency_code
        ORDER BY total_available_balance DESC
    ) AS balance_rank
FROM v_customer_balance_summary
ORDER BY currency_code, balance_rank, customer_name;

PROMPT 3. Monthly transfer trend with previous-period comparison
WITH monthly_totals AS (
    SELECT
        TRUNC(transferred_at, 'MM') AS transfer_month,
        original_currency AS currency_code,
        SUM(total_amount) AS total_debited
    FROM transfers
    WHERE status = 'COMPLETED'
    GROUP BY TRUNC(transferred_at, 'MM'), original_currency
)
SELECT
    transfer_month,
    currency_code,
    total_debited,
    LAG(total_debited) OVER (
        PARTITION BY currency_code
        ORDER BY transfer_month
    ) AS previous_month_total,
    total_debited - LAG(total_debited) OVER (
        PARTITION BY currency_code
        ORDER BY transfer_month
    ) AS month_over_month_change
FROM monthly_totals
ORDER BY currency_code, transfer_month;

PROMPT 4. Transaction category share by currency
WITH category_totals AS (
    SELECT
        original_currency AS currency_code,
        category,
        SUM(total_amount) AS category_total
    FROM transactions
    WHERE status = 'COMPLETED'
    GROUP BY original_currency, category
)
SELECT
    currency_code,
    category,
    category_total,
    ROUND(
        100 * RATIO_TO_REPORT(category_total) OVER (
            PARTITION BY currency_code
        ),
        2
    ) AS percentage_of_currency_spend
FROM category_totals
ORDER BY currency_code, category_total DESC;

PROMPT 5. Internal versus external transfer performance
SELECT
    transfer_type,
    COUNT(*) AS transfer_count,
    SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed_count,
    SUM(CASE WHEN status = 'PROCESSING' THEN 1 ELSE 0 END) AS processing_count,
    ROUND(AVG(original_amount), 2) AS average_original_amount,
    SUM(fee_amount) AS total_fees
FROM transfers
GROUP BY transfer_type
ORDER BY transfer_type;

PROMPT 6. Customers without a USD account using NOT EXISTS
SELECT
    c.customer_id,
    c.first_name,
    c.last_name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1
    FROM accounts a
    WHERE a.customer_id = c.customer_id
      AND a.currency_code = 'USD'
)
ORDER BY c.last_name, c.first_name;

PROMPT 7. All internal customers and external payees using UNION ALL
SELECT
    customer_id AS party_id,
    first_name || ' ' || last_name AS party_name,
    'CUSTOMER' AS party_type
FROM customers
UNION ALL
SELECT
    iban AS party_id,
    payee_name AS party_name,
    'EXTERNAL_PAYEE' AS party_type
FROM external_payees
ORDER BY party_type, party_name;

PROMPT 8. Customers who initiated both internal and external transfers
SELECT DISTINCT a.customer_id
FROM accounts a
JOIN transfers t ON t.source_iban = a.iban
WHERE t.transfer_type = 'INTERNAL'
INTERSECT
SELECT DISTINCT a.customer_id
FROM accounts a
JOIN transfers t ON t.source_iban = a.iban
WHERE t.transfer_type = 'EXTERNAL'
ORDER BY customer_id;

PROMPT 9. Accounts that have never initiated a transfer using MINUS
SELECT iban
FROM accounts
MINUS
SELECT source_iban
FROM transfers
ORDER BY iban;

PROMPT 10. Running outgoing activity total per account and currency
SELECT
    account_iban,
    activity_at,
    activity_type,
    reference_id,
    counterparty,
    amount,
    currency_code,
    SUM(amount + fee_amount) OVER (
        PARTITION BY account_iban, currency_code
        ORDER BY activity_at, reference_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_outgoing_total
FROM v_account_activity
WHERE direction = 'OUTGOING'
ORDER BY account_iban, currency_code, activity_at, reference_id;
