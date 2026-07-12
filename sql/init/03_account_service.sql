WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

CREATE OR REPLACE PACKAGE account_service AS
    FUNCTION is_valid_iban(p_iban IN VARCHAR2) RETURN BOOLEAN;

    FUNCTION get_available_balance(
        p_iban IN accounts.iban%TYPE
    ) RETURN accounts.available_balance%TYPE;

    FUNCTION count_customer_accounts(
        p_customer_id IN customers.customer_id%TYPE
    ) RETURN PLS_INTEGER;

    PROCEDURE open_account(
        p_iban             IN accounts.iban%TYPE,
        p_account_type     IN accounts.account_type%TYPE,
        p_currency_code    IN accounts.currency_code%TYPE,
        p_bic              IN accounts.bic%TYPE,
        p_customer_id      IN accounts.customer_id%TYPE,
        p_initial_balance  IN accounts.available_balance%TYPE DEFAULT 0
    );

    PROCEDURE close_account(
        p_iban IN accounts.iban%TYPE
    );

    PROCEDURE add_external_payee(
        p_iban        IN external_payees.iban%TYPE,
        p_payee_name  IN external_payees.payee_name%TYPE,
        p_bic         IN external_payees.bic%TYPE
    );
END account_service;
/

CREATE OR REPLACE PACKAGE BODY account_service AS
    FUNCTION normalize_iban(p_iban IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(REPLACE(TRIM(p_iban), ' ', ''));
    END normalize_iban;

    FUNCTION normalize_code(p_code IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(TRIM(p_code));
    END normalize_code;

    FUNCTION is_valid_iban(p_iban IN VARCHAR2) RETURN BOOLEAN IS
        v_iban VARCHAR2(34) := normalize_iban(p_iban);
    BEGIN
        RETURN REGEXP_LIKE(v_iban, '^[A-Z0-9]{15,34}$');
    END is_valid_iban;

    FUNCTION get_available_balance(
        p_iban IN accounts.iban%TYPE
    ) RETURN accounts.available_balance%TYPE IS
        v_iban    accounts.iban%TYPE := normalize_iban(p_iban);
        v_balance accounts.available_balance%TYPE;
    BEGIN
        SELECT available_balance
          INTO v_balance
          FROM accounts
         WHERE iban = v_iban;

        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Account not found: ' || p_iban);
    END get_available_balance;

    FUNCTION count_customer_accounts(
        p_customer_id IN customers.customer_id%TYPE
    ) RETURN PLS_INTEGER IS
        v_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM accounts
         WHERE customer_id = UPPER(TRIM(p_customer_id));

        RETURN v_count;
    END count_customer_accounts;

    PROCEDURE open_account(
        p_iban             IN accounts.iban%TYPE,
        p_account_type     IN accounts.account_type%TYPE,
        p_currency_code    IN accounts.currency_code%TYPE,
        p_bic              IN accounts.bic%TYPE,
        p_customer_id      IN accounts.customer_id%TYPE,
        p_initial_balance  IN accounts.available_balance%TYPE
    ) IS
        v_iban         accounts.iban%TYPE := normalize_iban(p_iban);
        v_customer_id  customers.customer_id%TYPE := UPPER(TRIM(p_customer_id));
        v_account_type accounts.account_type%TYPE := normalize_code(p_account_type);
        v_currency     accounts.currency_code%TYPE := normalize_code(p_currency_code);
        v_bic          accounts.bic%TYPE := normalize_code(p_bic);
        v_count        PLS_INTEGER;
    BEGIN
        IF NOT is_valid_iban(v_iban) THEN
            RAISE_APPLICATION_ERROR(-20002, 'Invalid IBAN format: ' || p_iban);
        END IF;

        IF p_initial_balance < 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Initial balance cannot be negative');
        END IF;

        SELECT COUNT(*)
          INTO v_count
          FROM customers
         WHERE customer_id = v_customer_id;

        IF v_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Customer not found: ' || p_customer_id);
        END IF;

        INSERT INTO accounts (
            iban,
            account_type,
            status,
            available_balance,
            currency_code,
            bic,
            opened_at,
            closed_at,
            customer_id
        ) VALUES (
            v_iban,
            v_account_type,
            'ACTIVE',
            p_initial_balance,
            v_currency,
            v_bic,
            SYSDATE,
            NULL,
            v_customer_id
        );
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20005, 'Account already exists: ' || p_iban);
    END open_account;

    PROCEDURE close_account(
        p_iban IN accounts.iban%TYPE
    ) IS
        v_iban     accounts.iban%TYPE := normalize_iban(p_iban);
        v_balance  accounts.available_balance%TYPE;
        v_status   accounts.status%TYPE;
    BEGIN
        SELECT available_balance, status
          INTO v_balance, v_status
          FROM accounts
         WHERE iban = v_iban
           FOR UPDATE;

        IF v_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20006, 'Account is already closed: ' || p_iban);
        END IF;

        IF v_balance <> 0 THEN
            RAISE_APPLICATION_ERROR(-20007, 'Account balance must be zero before closing');
        END IF;

        UPDATE accounts
           SET status = 'CLOSED',
               closed_at = SYSDATE
         WHERE iban = v_iban;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Account not found: ' || p_iban);
    END close_account;

    PROCEDURE add_external_payee(
        p_iban        IN external_payees.iban%TYPE,
        p_payee_name  IN external_payees.payee_name%TYPE,
        p_bic         IN external_payees.bic%TYPE
    ) IS
        v_iban  external_payees.iban%TYPE := normalize_iban(p_iban);
        v_bic   external_payees.bic%TYPE := normalize_code(p_bic);
    BEGIN
        IF NOT is_valid_iban(v_iban) THEN
            RAISE_APPLICATION_ERROR(-20008, 'Invalid payee IBAN format: ' || p_iban);
        END IF;

        IF NOT REGEXP_LIKE(v_bic, '^[A-Z0-9]{8}([A-Z0-9]{3})?$') THEN
            RAISE_APPLICATION_ERROR(-20009, 'Invalid BIC format: ' || p_bic);
        END IF;

        INSERT INTO external_payees (iban, payee_name, bic)
        VALUES (v_iban, TRIM(p_payee_name), v_bic);
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20010, 'External payee already exists: ' || p_iban);
    END add_external_payee;
END account_service;
/

SHOW ERRORS PACKAGE BODY account_service

PROMPT ACCOUNT_SERVICE package created successfully.