CREATE TABLE account_events (
    id          bigserial PRIMARY KEY,
    account_id  bigint      NOT NULL,
    kind        text        NOT NULL,
    payload     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL
);

CREATE INDEX index_account_events_on_account_id_and_occurred_at
    ON account_events (account_id, occurred_at DESC);
