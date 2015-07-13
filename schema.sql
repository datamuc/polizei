CREATE VIRTUAL TABLE meldungen_fts using fts4(meldung,title);
CREATE TABLE meldungen_idx (id char(40), ts datetime, meldung_docid integer);
CREATE UNIQUE INDEX midx_id on meldungen_idx(id);
CREATE INDEX midx_ts on meldungen_idx(ts);
