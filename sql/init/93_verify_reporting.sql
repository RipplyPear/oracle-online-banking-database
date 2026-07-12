WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

DECLARE
    v_valid_views     PLS_INTEGER;
    v_invalid_views   PLS_INTEGER;
    v_transfer_rows   PLS_INTEGER;
    v_activity_rows   PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_valid_views
      FROM all_objects
     WHERE owner = 'BANKING_APP'
       AND object_type = 'VIEW'
       AND object_name IN (
           'V_CUSTOMER_BALANCE_SUMMARY',
           'V_TRANSFER_DETAILS',
           'V_MONTHLY_CUSTOMER_OUTFLOW',
           'V_ACCOUNT_ACTIVITY'
       )
       AND status = 'VALID';

    SELECT COUNT(*)
      INTO v_invalid_views
      FROM all_objects
     WHERE owner = 'BANKING_APP'
       AND object_type = 'VIEW'
       AND object_name IN (
           'V_CUSTOMER_BALANCE_SUMMARY',
           'V_TRANSFER_DETAILS',
           'V_MONTHLY_CUSTOMER_OUTFLOW',
           'V_ACCOUNT_ACTIVITY'
       )
       AND status <> 'VALID';

    SELECT COUNT(*) INTO v_transfer_rows FROM v_transfer_details;
    SELECT COUNT(*) INTO v_activity_rows FROM v_account_activity;

    IF v_valid_views <> 4 OR v_invalid_views <> 0 THEN
        RAISE_APPLICATION_ERROR(
            -20301,
            'Expected 4 valid reporting views; valid=' || v_valid_views
            || ', invalid=' || v_invalid_views
        );
    END IF;

    IF v_transfer_rows <> 10 THEN
        RAISE_APPLICATION_ERROR(
            -20302,
            'Transfer detail view expected 10 rows, found ' || v_transfer_rows
        );
    END IF;

    IF v_activity_rows <> 26 THEN
        RAISE_APPLICATION_ERROR(
            -20303,
            'Account activity view expected 26 rows, found ' || v_activity_rows
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE('Reporting verification passed:');
    DBMS_OUTPUT.PUT_LINE('  Valid views:          ' || v_valid_views);
    DBMS_OUTPUT.PUT_LINE('  Transfer detail rows: ' || v_transfer_rows);
    DBMS_OUTPUT.PUT_LINE('  Activity rows:        ' || v_activity_rows);
END;
/

PROMPT Reporting verification completed successfully.
