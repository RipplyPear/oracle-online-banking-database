WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

DECLARE
    v_customers         PLS_INTEGER;
    v_accounts          PLS_INTEGER;
    v_external_payees   PLS_INTEGER;
    v_transfers         PLS_INTEGER;
    v_transactions      PLS_INTEGER;
    v_orphaned_accounts PLS_INTEGER;
    v_invalid_amounts   PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_customers FROM customers;
    SELECT COUNT(*) INTO v_accounts FROM accounts;
    SELECT COUNT(*) INTO v_external_payees FROM external_payees;
    SELECT COUNT(*) INTO v_transfers FROM transfers;
    SELECT COUNT(*) INTO v_transactions FROM transactions;

    SELECT COUNT(*)
      INTO v_orphaned_accounts
      FROM accounts a
      LEFT JOIN customers c ON c.customer_id = a.customer_id
     WHERE c.customer_id IS NULL;

    SELECT
        (SELECT COUNT(*)
           FROM transfers
          WHERE ABS(converted_amount - ROUND(original_amount * exchange_rate, 2)) > 0.01
             OR ABS(total_amount - (converted_amount + fee_amount)) > 0.01)
        +
        (SELECT COUNT(*)
           FROM transactions
          WHERE ABS(converted_amount - ROUND(original_amount * exchange_rate, 2)) > 0.01
             OR ABS(total_amount - (converted_amount + fee_amount)) > 0.01)
      INTO v_invalid_amounts
      FROM dual;

    IF v_customers <> 11 THEN
        RAISE_APPLICATION_ERROR(-20101, 'Expected 11 customers, found ' || v_customers);
    END IF;

    IF v_accounts <> 13 THEN
        RAISE_APPLICATION_ERROR(-20102, 'Expected 13 accounts, found ' || v_accounts);
    END IF;

    IF v_external_payees <> 5 THEN
        RAISE_APPLICATION_ERROR(
            -20103,
            'Expected 5 external payees, found ' || v_external_payees
        );
    END IF;

    IF v_transfers <> 10 THEN
        RAISE_APPLICATION_ERROR(-20104, 'Expected 10 transfers, found ' || v_transfers);
    END IF;

    IF v_transactions <> 11 THEN
        RAISE_APPLICATION_ERROR(
            -20105,
            'Expected 11 transactions, found ' || v_transactions
        );
    END IF;

    IF v_orphaned_accounts <> 0 THEN
        RAISE_APPLICATION_ERROR(
            -20106,
            'Found ' || v_orphaned_accounts || ' accounts without a customer'
        );
    END IF;

    IF v_invalid_amounts <> 0 THEN
        RAISE_APPLICATION_ERROR(
            -20107,
            'Found ' || v_invalid_amounts || ' rows with inconsistent calculated amounts'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('Seed data verification passed:');
    DBMS_OUTPUT.PUT_LINE('  Customers:       ' || v_customers);
    DBMS_OUTPUT.PUT_LINE('  Accounts:        ' || v_accounts);
    DBMS_OUTPUT.PUT_LINE('  External payees: ' || v_external_payees);
    DBMS_OUTPUT.PUT_LINE('  Transfers:       ' || v_transfers);
    DBMS_OUTPUT.PUT_LINE('  Transactions:    ' || v_transactions);
END;
/

PROMPT Seed data verification completed successfully.