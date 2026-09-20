-- Phase multi-device : chaque clé device porte son canal (overlay/bot) et
-- n'authentifie que ses propres matchs. La clé « marc » (migration 2) garde
-- le canal par défaut ; la 2e ligne = build « ami » FR55 (clé brute jamais
-- committée, hash SHA-256 uniquement — cf. scripts/build-release.sh FRIEND=1).
alter table devices add column channel text not null default 'marc';

insert into devices (id, device_key_hash, label, channel) values
  (2, '437308e763d33ee71ecbecfe14c0689daaef01ace30c0a17f345bc924c05cdb0', 'FR55 ami', 'ami');
