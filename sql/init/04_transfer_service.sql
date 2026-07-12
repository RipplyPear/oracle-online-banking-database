WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

CREATE OR REPLACE PACKAGE transfer_service AS
    FUNCTION execute_internal_transfer(
        p_source_iban       IN accounts.iban%TYPE,
        p_destination_iban  IN accounts.iban%TYPE,
        p_amount            IN transfers.original_amount%TYPE,
        p_exchange_rate     IN transfers.exchange_rate%TYPE DEFAULT NULL,
        p_fee_amount        IN transfers.fee_amount%TYPE DEFAULT 0,
        p_description       IN transfers.description%TYPE DEFAULT NULL
    ) RETURN transfers.transfer_id%TYPE;

    FUNCTION execute_external_transfer(
        p_source_iban       IN accounts.iban%TYPE,
        p_payee_iban        IN external_payees.iban%TYPE,
        p_amount            IN transfers.original_amount%TYPE,
        p_target_currency   IN transfers.target_currency%TYPE,
        p_exchange_rate     IN transfers.exchange_rate%TYPE DEFAULT NULL,
        p_fee_amount        IN transfers.fee_amount%TYPE DEFAULT 0,
        p_description       IN transfers.description%TYPE DEFAULT NULL
    ) RETURN transfers.transfer_id%TYPE;

    FUNCTION count_customer_transfers(
        p_customer_id IN customers.customer_id%TYPE
    ) RETURN PLS_INTEGER;

    FUNCTION get_monthly_average(
        p_year   IN PLS_INTEGER,
        p_month  IN PLS_INTEGER
    ) RETURN NUMBER;

    PROCEDURE print_monthly_report(
        p_year IN PLS_INTEGER
    );
END transfer_service;
/

CREATE OR REPLACE PACKAGE BODY transfer_service AS
    TYPE account_lock_record IS RECORD (
        status            accounts.status%TYPE,
        available_balance accounts.available_balance%TYPE,
        currency_code     accounts.currency_code%TYPE
    );

    FUNCTION normalize_iban(p_iban IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(REPLACE(TRIM(p_iban), ' ', ''));
    END normalize_iban;

    FUNCTION normalize_code(p_code IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(TRIM(p_code));
    END normalize_code;

    PROCEDURE lock_account(
        p_iban     IN accounts.iban%TYPE,
        p_account  OUT account_lock_record
    ) IS
    BEGIN
        SELECT status, available_balance, currency_code
          INTO p_account.status, p_account.available_balance, p_account.currency_code
          FROM accounts
         WHERE iban = p_iban
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20101, 'Account not found: ' || p_iban);
    END lock_account;

    FUNCTION resolve_exchange_rate(
        p_source_currency  IN accounts.currency_code%TYPE,
        p_target_currency  IN accounts.currency_code%TYPE,
        p_exchange_rate    IN transfers.exchange_rate%TYPE
    ) RETURN transfers.exchange_rate%TYPE IS
    BEGIN
        IF p_source_currency = p_target_currency THEN
            IF p_exchange_rate IS NOT NULL AND p_exchange_rate <> 1 THEN
                RAISE_APPLICATION_ERROR(
                    -20102,
                    'Exchange rate must be 1 for matching currencies'
                );
            END IF;

            RETURN 1;
        END IF;

        IF p_exchange_rate IS NULL OR p_exchange_rate <= 0 THEN
            RAISE_APPLICATION_ERROR(
                -20103,
                'A positive exchange rate is required for different currencies'
            );
        END IF;

        RETURN p_exchange_rate;
    END resolve_exchange_rate;

    PROCEDURE validate_amounts(
        p_amount      IN transfers.original_amount%TYPE,
        p_fee_amount  IN transfers.fee_amount%TYPE
    ) IS
    BEGIN
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20104, 'Transfer amount must be positive');
        END IF;

        IF p_fee_amount IS NULL OR p_fee_amount < 0 THEN
            RAISE_APPLICATION_ERROR(-20105, 'Fee amount cannot be negative');
        END IF;
    END validate_amounts;

    PROCEDURE validate_active_account(
        p_iban     IN accounts.iban%TYPE,
        p_account  IN account_lock_record
    ) IS
    BEGIN
        IF p_account.status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20106, 'Account is not active: ' || p_iban);
        END IF;
    END validate_active_account;

    FUNCTION next_transfer_id RETURN transfers.transfer_id%TYPE IS
    BEGIN
        RETURN 'TRF' || LPAD(seq_transfers.NEXTVAL, 9, '0');
    END next_transfer_id;

    FUNCTION execute_internal_transfer(
        p_source_iban       IN accounts.iban%TYPE,
        p_destination_iban  IN accounts.iban%TYPE,
        p_amount            IN transfers.original_amount%TYPE,
        p_exchange_rate     IN transfers.exchange_rate%TYPE,
        p_fee_amount        IN transfers.fee_amount%TYPE,
        p_description       IN transfers.description%TYPE
    ) RETURN transfers.transfer_id%TYPE IS
        v_source_iban       accounts.iban%TYPE := normalize_iban(p_source_iban);
        v_destination_iban  accounts.iban%TYPE := normalize_iban(p_destination_iban);
        v_source            account_lock_record;
        v_destination       account_lock_record;
        v_rate              transfers.exchange_rate%TYPE;
        v_converted_amount  transfers.converted_amount%TYPE;
        v_total_amount      transfers.total_amount%TYPE;
        v_transfer_id       transfers.transfer_id%TYPE;
    BEGIN
        SAVEPOINT before_internal_transfer;
        validate_amounts(p_amount, p_fee_amount);

        IF v_source_iban = v_destination_iban THEN
            RAISE_APPLICATION_ERROR(-20107, 'Source and destination accounts must differ');
        END IF;

        -- Lock in lexical order to prevent deadlocks between reciprocal transfers.
        IF v_source_iban < v_destination_iban THEN
            lock_account(v_source_iban, v_source);
            lock_account(v_destination_iban, v_destination);
        ELSE
            lock_account(v_destination_iban, v_destination);
            lock_account(v_source_iban, v_source);
        END IF;

        validate_active_account(v_source_iban, v_source);
        validate_active_account(v_destination_iban, v_destination);

        v_rate := resolve_exchange_rate(
            v_source.currency_code,
            v_destination.currency_code,
            p_exchange_rate
        );
        v_converted_amount := ROUND(p_amount * v_rate, 2);
        v_total_amount := p_amount + p_fee_amount;

        IF v_source.available_balance < v_total_amount THEN
            RAISE_APPLICATION_ERROR(-20108, 'Insufficient funds in account: ' || v_source_iban);
        END IF;

        UPDATE accounts
           SET available_balance = available_balance - v_total_amount
         WHERE iban = v_source_iban;

        UPDATE accounts
           SET available_balance = available_balance + v_converted_amount
         WHERE iban = v_destination_iban;

        v_transfer_id := next_transfer_id;

        INSERT INTO transfers (
            transfer_id,
            transfer_type,
            transferred_at,
            status,
            description,
            original_amount,
            original_currency,
            converted_amount,
            target_currency,
            exchange_rate,
            fee_amount,
            total_amount,
            source_iban,
            destination_account_iban,
            destination_payee_iban
        ) VALUES (
            v_transfer_id,
            'INTERNAL',
            SYSTIMESTAMP,
            'COMPLETED',
            p_description,
            p_amount,
            v_source.currency_code,
            v_converted_amount,
            v_destination.currency_code,
            v_rate,
            p_fee_amount,
            v_total_amount,
            v_source_iban,
            v_destination_iban,
            NULL
        );

        RETURN v_transfer_id;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO before_internal_transfer;
            RAISE;
    END execute_internal_transfer;

    FUNCTION execute_external_transfer(
        p_source_iban       IN accounts.iban%TYPE,
        p_payee_iban        IN external_payees.iban%TYPE,
        p_amount            IN transfers.original_amount%TYPE,
        p_target_currency   IN transfers.target_currency%TYPE,
        p_exchange_rate     IN transfers.exchange_rate%TYPE,
        p_fee_amount        IN transfers.fee_amount%TYPE,
        p_description       IN transfers.description%TYPE
    ) RETURN transfers.transfer_id%TYPE IS
        v_source_iban       accounts.iban%TYPE := normalize_iban(p_source_iban);
        v_payee_iban        external_payees.iban%TYPE := normalize_iban(p_payee_iban);
        v_target_currency   transfers.target_currency%TYPE := normalize_code(p_target_currency);
        v_source            account_lock_record;
        v_payee_count       PLS_INTEGER;
        v_rate              transfers.exchange_rate%TYPE;
        v_converted_amount  transfers.converted_amount%TYPE;
        v_total_amount      transfers.total_amount%TYPE;
        v_transfer_id       transfers.transfer_id%TYPE;
    BEGIN
        SAVEPOINT before_external_transfer;
        validate_amounts(p_amount, p_fee_amount);

        lock_account(v_source_iban, v_source);
        validate_active_account(v_source_iban, v_source);

        SELECT COUNT(*)
          INTO v_payee_count
          FROM external_payees
         WHERE iban = v_payee_iban;

        IF v_payee_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20109, 'External payee not found: ' || p_payee_iban);
        END IF;

        IF NOT REGEXP_LIKE(v_target_currency, '^[A-Z]{3}$') THEN
            RAISE_APPLICATION_ERROR(-20110, 'Invalid target currency: ' || p_target_currency);
        END IF;

        v_rate := resolve_exchange_rate(
            v_source.currency_code,
            v_target_currency,
            p_exchange_rate
        );
        v_converted_amount := ROUND(p_amount * v_rate, 2);
        v_total_amount := p_amount + p_fee_amount;

        IF v_source.available_balance < v_total_amount THEN
            RAISE_APPLICATION_ERROR(-20108, 'Insufficient funds in account: ' || v_source_iban);
        END IF;

        UPDATE accounts
           SET available_balance = available_balance - v_total_amount
         WHERE iban = v_source_iban;

        v_transfer_id := next_transfer_id;

        INSERT INTO transfers (
            transfer_id,
            transfer_type,
            transferred_at,
            status,
            description,
            original_amount,
            original_currency,
            converted_amount,
            target_currency,
            exchange_rate,
            fee_amount,
            total_amount,
            source_iban,
            destination_account_iban,
            destination_payee_iban
        ) VALUES (
            v_transfer_id,
            'EXTERNAL',
            SYSTIMESTAMP,
            'COMPLETED',
            p_description,
            p_amount,
            v_source.currency_code,
            v_converted_amount,
            v_target_currency,
            v_rate,
            p_fee_amount,
            v_total_amount,
            v_source_iban,
            NULL,
            v_payee_iban
        );

        RETURN v_transfer_id;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO before_external_transfer;
            RAISE;
    END execute_external_transfer;

    FUNCTION count_customer_transfers(
        p_customer_id IN customers.customer_id%TYPE
    ) RETURN PLS_INTEGER IS
        v_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM transfers t
          JOIN accounts a ON a.iban = t.source_iban
         WHERE a.customer_id = UPPER(TRIM(p_customer_id));

        RETURN v_count;
    END count_customer_transfers;

    FUNCTION get_monthly_average(
        p_year   IN PLS_INTEGER,
        p_month  IN PLS_INTEGER
    ) RETURN NUMBER IS
        v_average NUMBER;
    BEGIN
        IF p_month NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(-20111, 'Month must be between 1 and 12');
        END IF;

        SELECT NVL(AVG(original_amount), 0)
          INTO v_average
          FROM transfers
         WHERE transferred_at >= TO_TIMESTAMP(
                   p_year || '-' || LPAD(p_month, 2, '0') || '-01',
                   'YYYY-MM-DD'
               )
           AND transferred_at < ADD_MONTHS(
                   TO_TIMESTAMP(
                       p_year || '-' || LPAD(p_month, 2, '0') || '-01',
                       'YYYY-MM-DD'
                   ),
                   1
               );

        RETURN ROUND(v_average, 2);
    END get_monthly_average;

    PROCEDURE print_monthly_report(
        p_year IN PLS_INTEGER
    ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Month   | Transfers | Original amount');
        DBMS_OUTPUT.PUT_LINE('--------+-----------+----------------');

        FOR report_row IN (
            SELECT TO_CHAR(transferred_at, 'YYYY-MM') AS report_month,
                   COUNT(*) AS transfer_count,
                   SUM(original_amount) AS total_original_amount
              FROM transfers
             WHERE transferred_at >= TO_TIMESTAMP(p_year || '-01-01', 'YYYY-MM-DD')
               AND transferred_at < TO_TIMESTAMP((p_year + 1) || '-01-01', 'YYYY-MM-DD')
             GROUP BY TO_CHAR(transferred_at, 'YYYY-MM')
             ORDER BY report_month
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                report_row.report_month || ' | '
                || LPAD(report_row.transfer_count, 9) || ' | '
                || TO_CHAR(report_row.total_original_amount, '9999999990.00')
            );
        END LOOP;
    END print_monthly_report;
END transfer_service;
/

SHOW ERRORS PACKAGE BODY transfer_service

PROMPT TRANSFER_SERVICE package created successfully.