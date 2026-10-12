ALTER TABLE account_events
    ADD CONSTRAINT account_events_kind_present CHECK (kind <> '');
