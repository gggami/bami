rename table msg to messages;
rename table special_msg to special_messages;

alter table messages add column weight tinyint not null default 1 after keyword;
alter table messages add column weight tinyint not null default 1 after keyword;

alter table messages add index weight_idx(weight);
alter table special_messages add index weight_idx(weight);
