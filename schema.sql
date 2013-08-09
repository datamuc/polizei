/*
 * -----------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <m@rbfh.de> wrote this file. As long as you retain this notice you can
 * do whatever you want with this stuff. If we meet some day, and you
 * think this stuff is worth it, you can buy me a beer in return
 * Danijel Tasov
 * -----------------------------------------------------------------------
*/
CREATE TABLE meldungen (id char(40), title text, meldung text, ts datetime);
CREATE UNIQUE INDEX m_id on meldungen (id);
