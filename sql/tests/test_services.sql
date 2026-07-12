WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_source_before       accounts.available_balance%TYPE;
    v_destination_before  accounts.available_balance%TYPE;
    v_source_after        accounts.available_balance%TYPE;
    v_destination_after   accounts.available_balance%TYPE;
    v_transfer_count      PLS_INTEGER;
    v_transfer_id         transfers.transfer_id%TYPE;

    PROCEDURE assert_true(
        p_condition  IN BOOLEAN,
        p_message    IN VARCHAR2
    ) IS
    BEGIN
        IF NOT p_condition THEN
            RAISE_APPLICATION_ERROR(-20901, p_message);
        END IF;
    END assert_true;

    PROCEDURE assert_number(
        p_actual    IN NUMBER,
        p_expected  IN NUMBER,
        p_message   IN VARCHAR2
    ) IS
    BEGIN
        IF ABS(p_actual - p_expected) > 0.01 THEN
            RAISE_APPLICATION_ERROR(
                -20902,
                p_message || ': expected ' || p_expected || ', found ' || p_actual
            );
        END IF;
    END assert_number;
BEGIN
    SAVEPOINT service_test_start;

    DBMS_OUTPUT.PUT_LINE('Running ACCOUNT_SERVICE tests...');

    assert_true(
        account_service.is_valid_iban('RO49 AAAA 1B31 0075 9384 0001'),
        'A valid formatted IBAN was rejected'
    );
    assert_true(
        NOT account_service.is_valid_iban('INVALID'),
        'An invalid IBAN was accepted'
    );
    assert_number(
        account_service.get_available_balance('RO49 AAAA 1B31 0075 9384 0001'),
        1242.12,
        'Unexpected initial account balance'
    );
    assert_number(
        account_service.count_customer_accounts('CUS002'),
        2,
        'Unexpected account count for CUS002'
    );

    account_service.open_account(
        p_iban            => 'RO49 AAAA 1B31 0075 9384 0099',
        p_account_type    => 'savings',
        p_currency_code   => 'eur',
        p_bic             => 'aaaarobu',
        p_customer_id     => 'CUS001',
        p_initial_balance => 0
    );
    assert_number(
        account_service.count_customer_accounts('CUS001'),
        2,
        'Opening an account did not update the account count'
    );

    account_service.close_account('RO49AAAA1B31007593840099');

    DECLARE
        v_status accounts.status%TYPE;
    BEGIN
        SELECT status
          INTO v_status
          FROM accounts
         WHERE iban = 'RO49AAAA1B31007593840099';

        assert_true(v_status = 'CLOSED', 'Zero-balance account was not closed');
    END;

    account_service.add_external_payee(
        p_iban       => 'IT60X0542811101000000123456',
        p_payee_name => 'Contoso Italia SRL',
        p_bic        => 'BPPIITRR'
    );

    DBMS_OUTPUT.PUT_LINE('ACCOUNT_SERVICE tests passed.');
    DBMS_OUTPUT.PUT_LINE('Running TRANSFER_SERVICE tests...');

    SELECT available_balance
      INTO v_source_before
      FROM accounts
     WHERE iban = 'RO49AAAA1B31007593840001';

    SELECT available_balance
      INTO v_destination_before
      FROM accounts
     WHERE iban = 'RO49AAAA1B31007593840002';

    SELECT COUNT(*) INTO v_transfer_count FROM transfers;

    v_transfer_id := transfer_service.execute_internal_transfer(
        p_source_iban      => 'RO49 AAAA 1B31 0075 9384 0001',
        p_destination_iban => 'RO49AAAA1B31007593840002',
        p_amount           => 100,
        p_fee_amount       => 2,
        p_description      => 'Automated same-currency test'
    );

    SELECT available_balance
      INTO v_source_after
      FROM accounts
     WHERE iban = 'RO49AAAA1B31007593840001';

    SELECT available_balance
      INTO v_destination_after
      FROM accounts
     WHERE iban = 'RO49AAAA1B31007593840002';

    assert_number(
        v_source_after,
        v_source_before - 102,
        'Internal transfer debited an incorrect source amount'
    );
    assert_number(
        v_destination_after,
        v_destination_before + 100,
        'Internal transfer credited an incorrect destination amount'
    );

    DECLARE
        v_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM transfers
         WHERE transfer_id = v_transfer_id
           AND transfer_type = 'INTERNAL'
           AND status = 'COMPLETED'
           AND total_amount = 102;

        assert_number(v_count, 1, 'Internal transfer record was not created correctly');
    END;

    v_transfer_id := transfer_service.execute_internal_transfer(
        p_source_iban      => 'RO49AAAA1B31007593840003',
        p_destination_iban => 'RO49AAAA1B31007593840004',
        p_amount           => 100,
        p_exchange_rate    => 0.20,
        p_fee_amount       => 1,
        p_description      => 'Automated cross-currency test'
    );

    DECLARE
        v_converted transfers.converted_amount%TYPE;
        v_total     transfers.total_amount%TYPE;
    BEGIN
        SELECT converted_amount, total_amount
          INTO v_converted, v_total
          FROM transfers
         WHERE transfer_id = v_transfer_id;

        assert_number(v_converted, 20, 'Converted amount is incorrect');
        assert_number(v_total, 101, 'Debited total is incorrect');
    END;

    v_transfer_id := transfer_service.execute_external_transfer(
        p_source_iban     => 'RO49AAAA1B31007593840001',
        p_payee_iban      => 'DE89370400440532013000',
        p_amount          => 100,
        p_target_currency => 'EUR',
        p_exchange_rate   => 0.20,
        p_fee_amount      => 1,
        p_description     => 'Automated external transfer test'
    );

    DECLARE
        v_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM transfers
         WHERE transfer_id = v_transfer_id
           AND transfer_type = 'EXTERNAL'
           AND destination_payee_iban = 'DE89370400440532013000'
           AND converted_amount = 20
           AND total_amount = 101;

        assert_number(v_count, 1, 'External transfer record was not created correctly');
    END;

    BEGIN
        v_transfer_id := transfer_service.execute_internal_transfer(
            p_source_iban      => 'RO49AAAA1B31007593840006',
            p_destination_iban => 'RO49AAAA1B31007593840002',
            p_amount           => 999999,
            p_exchange_rate    => 1,
            p_fee_amount       => 0,
            p_description      => 'Expected insufficient-funds failure'
        );

        RAISE_APPLICATION_ERROR(-20903, 'Insufficient-funds transfer unexpectedly succeeded');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20108 THEN
                RAISE;
            END IF;
    END;

    SELECT COUNT(*)
      INTO v_transfer_count
      FROM transfers
     WHERE description = 'Expected insufficient-funds failure';

    assert_number(
        v_transfer_count,
        0,
        'Failed transfer left a transfer record behind'
    );

    DBMS_OUTPUT.PUT_LINE('TRANSFER_SERVICE tests passed.');

    ROLLBACK TO service_test_start;

    SELECT COUNT(*)
      INTO v_transfer_count
      FROM transfers;

    assert_number(v_transfer_count, 10, 'Rollback did not restore the seeded transfers');
    assert_number(
        account_service.get_available_balance('RO49AAAA1B31007593840001'),
        1242.12,
        'Rollback did not restore the source balance'
    );

    DBMS_OUTPUT.PUT_LINE('Rollback verification passed.');
    DBMS_OUTPUT.PUT_LINE('All service tests passed successfully.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO service_test_start;
        DBMS_OUTPUT.PUT_LINE('Service tests failed: ' || SQLERRM);
        RAISE;
END;
/

EXIT SUCCESS