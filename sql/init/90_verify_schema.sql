WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = BANKING_APP;

DECLARE
    v_table_count      PLS_INTEGER;
    v_sequence_count   PLS_INTEGER;
    v_constraint_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_table_count
      FROM all_tables
     WHERE owner = 'BANKING_APP'
       AND table_name IN (
           'CUSTOMERS',
           'ACCOUNTS',
           'EXTERNAL_PAYEES',
           'TRANSFERS',
           'TRANSACTIONS'
       );

    SELECT COUNT(*)
      INTO v_sequence_count
      FROM all_sequences
     WHERE sequence_owner = 'BANKING_APP'
       AND sequence_name IN ('SEQ_TRANSFERS', 'SEQ_TRANSACTIONS');

    SELECT COUNT(*)
      INTO v_constraint_count
      FROM all_constraints
     WHERE owner = 'BANKING_APP'
       AND status = 'ENABLED'
       AND table_name IN (
           'CUSTOMERS',
           'ACCOUNTS',
           'EXTERNAL_PAYEES',
           'TRANSFERS',
           'TRANSACTIONS'
       );

    IF v_table_count <> 5 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Expected 5 tables, found ' || v_table_count);
    END IF;

    IF v_sequence_count <> 2 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Expected 2 sequences, found ' || v_sequence_count);
    END IF;

    IF v_constraint_count < 25 THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Expected at least 25 enabled constraints, found ' || v_constraint_count
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'Schema verification passed: '
        || v_table_count || ' tables, '
        || v_sequence_count || ' sequences, '
        || v_constraint_count || ' enabled constraints.'
    );
END;
/

PROMPT Schema verification completed successfully.