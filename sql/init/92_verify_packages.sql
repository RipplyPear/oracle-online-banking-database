WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

DECLARE
    v_valid_objects  PLS_INTEGER;
    v_compile_errors PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_valid_objects
      FROM all_objects
     WHERE owner = 'BANKING_APP'
       AND object_name IN ('ACCOUNT_SERVICE', 'TRANSFER_SERVICE')
       AND object_type IN ('PACKAGE', 'PACKAGE BODY')
       AND status = 'VALID';

    SELECT COUNT(*)
      INTO v_compile_errors
      FROM all_errors
     WHERE owner = 'BANKING_APP'
       AND name IN ('ACCOUNT_SERVICE', 'TRANSFER_SERVICE');

    IF v_valid_objects <> 4 THEN
        RAISE_APPLICATION_ERROR(
            -20201,
            'Expected 4 valid package objects, found ' || v_valid_objects
        );
    END IF;

    IF v_compile_errors <> 0 THEN
        RAISE_APPLICATION_ERROR(
            -20202,
            'Package compilation produced ' || v_compile_errors || ' errors'
        );
    END IF;

    IF NOT account_service.is_valid_iban('RO49 AAAA 1B31 0075 9384 0001') THEN
        RAISE_APPLICATION_ERROR(-20203, 'IBAN normalization test failed');
    END IF;

    IF account_service.count_customer_accounts('CUS002') <> 2 THEN
        RAISE_APPLICATION_ERROR(-20204, 'Customer account count test failed');
    END IF;

    IF transfer_service.count_customer_transfers('CUS009') <> 1 THEN
        RAISE_APPLICATION_ERROR(-20205, 'Customer transfer count test failed');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Package verification passed:');
    DBMS_OUTPUT.PUT_LINE('  Valid package objects: ' || v_valid_objects);
    DBMS_OUTPUT.PUT_LINE('  Compilation errors:    ' || v_compile_errors);
    DBMS_OUTPUT.PUT_LINE('  Read-only tests:        3 passed');
END;
/

PROMPT Package verification completed successfully.