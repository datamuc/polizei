CREATE TABLE meldungen (id char(40), title text, meldung text, ts datetime);
CREATE UNIQUE INDEX m_id on meldungen (id);
