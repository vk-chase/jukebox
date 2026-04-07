CREATE TABLE IF NOT EXISTS `chasemusicbox` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `item` VARCHAR(64) NOT NULL,
  `station_type` VARCHAR(64) NOT NULL,
  `station_name` VARCHAR(64) NULL DEFAULT NULL,
  `model` VARCHAR(100) NOT NULL,
  `x` DECIMAL(10,4) NOT NULL,
  `y` DECIMAL(10,4) NOT NULL,
  `z` DECIMAL(10,4) NOT NULL,
  `heading` DECIMAL(7,3) NOT NULL DEFAULT 0.000,
  `volume` DECIMAL(4,3) NOT NULL DEFAULT 0.200,
  `radius` SMALLINT UNSIGNED NOT NULL DEFAULT 20,
  `history_json` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_owner` (`citizenid`),
  KEY `idx_item` (`item`),
  KEY `idx_station_type` (`station_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `chasemusicbox`
  ADD COLUMN IF NOT EXISTS `station_type` VARCHAR(64) NOT NULL DEFAULT 'jukeboxone' AFTER `item`,
  ADD COLUMN IF NOT EXISTS `station_name` VARCHAR(64) NULL DEFAULT NULL AFTER `station_type`,
  ADD COLUMN IF NOT EXISTS `history_json` LONGTEXT NOT NULL AFTER `radius`,
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`;

UPDATE `chasemusicbox`
SET `station_type` = CASE
  WHEN `station_type` IS NULL OR `station_type` = '' THEN COALESCE(NULLIF(`item`, ''), 'jukeboxone')
  ELSE `station_type`
END;

UPDATE `chasemusicbox`
SET `history_json` = '[]'
WHERE `history_json` IS NULL OR `history_json` = '';
