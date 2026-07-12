# Design decisions

## Oracle in a container

The project runs Oracle in Docker rather than requiring a native database installation or access to a university server. The database version, initialization order, schema user, and persistent storage are declared in `compose.yaml`.

This makes the project reproducible locally and in continuous integration while keeping Oracle-specific SQL and PL/SQL features.

## Transfers and merchant transactions are separate

Transfers and merchant transactions share monetary attributes but represent different business events:

- a transfer has a known source and either an internal account or external payee destination;
- a merchant transaction belongs to one account and records a merchant and category.

Keeping them separate avoids nullable merchant fields on transfers and nullable destination-account fields on card transactions. `V_ACCOUNT_ACTIVITY` provides a unified read model when consumers need a combined history.

## Monetary values are not aggregated across currencies

Balances and flows are grouped or partitioned by `currency_code`. Adding RON, EUR, and USD values without converting them to a common currency would produce a numerically valid but financially meaningless result.

For a converted operation:

```text
converted_amount = ROUND(original_amount * exchange_rate, 2)
total_amount     = original_amount + fee_amount
```

Fees are represented in the source currency, and `total_amount` is the source-account debit.

## Destination integrity

Every transfer has exactly one destination:

- `destination_account_iban` for an `INTERNAL` transfer;
- `destination_payee_iban` for an `EXTERNAL` transfer.

A check constraint enforces both the exclusive-or relationship and its agreement with `transfer_type`.

## Transaction concurrency

Internal transfers lock both account rows with `SELECT ... FOR UPDATE`. Locks are acquired in lexical IBAN order, independent of which account is the source. Reciprocal transfers therefore request locks in the same order, reducing deadlock risk.

Validations and data changes run after the locks are acquired. A local savepoint restores the operation's changes if an exception occurs. The caller retains control over the final transaction commit.

## Indexing foreign keys

Oracle does not automatically index foreign-key columns. Explicit indexes support joins and reduce locking problems when parent rows are modified. Additional date and category indexes support the reporting access patterns demonstrated by the project.

## Synthetic data

Seed records use fictional identities and `example.com` email addresses. Transfer dates span several months so analytical window functions produce meaningful output. The seed script is deterministic, making verification counts stable across environments.

## Automated initialization

Files under `sql/init` run once, in lexical order, when the Oracle data volume is first created. Each script exits on SQL errors. Later verification scripts query Oracle metadata and seeded rows, preventing an invalid package or incomplete dataset from being reported as a successful build.

Service tests are kept outside `sql/init` because they are executable verification, not database state. Their data changes are rolled back after assertions.
