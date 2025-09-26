-- Stations table
CREATE TABLE IF NOT EXISTS `music_stations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `item` VARCHAR(64) NOT NULL,                 -- which usable item placed it
  `model` VARCHAR(100) NOT NULL,               -- prop model (name or hash as string)
  `x` DECIMAL(9,4) NOT NULL,
  `y` DECIMAL(9,4) NOT NULL,
  `z` DECIMAL(9,4) NOT NULL,
  `heading` DECIMAL(6,3) NOT NULL DEFAULT 0.000,
  `volume` DECIMAL(4,3) NOT NULL DEFAULT 0.200, -- 0.000–1.000
  `radius` SMALLINT UNSIGNED NOT NULL DEFAULT 30,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_owner` (`citizenid`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Song history per station (keep newest N; server trims to N)
CREATE TABLE IF NOT EXISTS `music_station_history` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `station_id` INT UNSIGNED NOT NULL,
  `url` VARCHAR(255) NOT NULL,
  `played_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_station_url` (`station_id`, `url`),
  KEY `idx_station_time` (`station_id`, `played_at` DESC),
  CONSTRAINT `fk_history_station`
    FOREIGN KEY (`station_id`) REFERENCES `music_stations`(`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
