-- ============================================================
-- HoleReport / MeasureSnap — PostgreSQL schema
-- Run: psql -U holereport -d holereport -f schema.sql
-- Run once: psql -U holereport -d holereport -f schema.sql
--
-- photos and users tables already exist in the DB.
-- This file creates only the districts table (new) and adds
-- the status column to photos if it was missing.
-- ============================================================

-- Photo categories
CREATE TABLE IF NOT EXISTS categories (
  id         SERIAL PRIMARY KEY,
  slug       VARCHAR(100)  NOT NULL UNIQUE,
  name       VARCHAR(255)  NOT NULL,
  name_en    VARCHAR(255)  DEFAULT '',
  color      VARCHAR(20)   DEFAULT '#3b82f6',
  sort_order INTEGER       DEFAULT 0,
  is_active  BOOLEAN       NOT NULL DEFAULT true
);

-- Add parent_id to districts for tree structure
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'districts' AND column_name = 'parent_id'
  ) THEN
    ALTER TABLE districts ADD COLUMN parent_id INTEGER REFERENCES districts(id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_districts_parent    ON districts(parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_slug     ON categories(slug);
CREATE INDEX IF NOT EXISTS idx_categories_active   ON categories(is_active);

-- Add category_id FK to photos
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'photos' AND column_name = 'category_id'
  ) THEN
    ALTER TABLE photos ADD COLUMN category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_photos_category ON photos(category_id);

-- Districts (map zones)
CREATE TABLE IF NOT EXISTS districts (
  id          SERIAL PRIMARY KEY,
  slug        VARCHAR(100)  NOT NULL UNIQUE,
  name        VARCHAR(255)  NOT NULL,
  name_en     VARCHAR(255)  DEFAULT '',
  color       VARCHAR(20)   DEFAULT '#3b82f6',
  city        VARCHAR(255)  DEFAULT '',
  sort_order  INTEGER       DEFAULT 0,
  coordinates JSONB         NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_districts_slug ON districts(slug);

-- Add status column to photos if it does not yet exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'photos' AND column_name = 'status'
  ) THEN
    ALTER TABLE photos ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'new'
      CHECK (status IN ('new','in_progress','resolved','closed'));
  END IF;
END;
$$;

-- Add user_type, user_mail, user_password to users if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'user_type'
  ) THEN
    ALTER TABLE users ADD COLUMN user_type VARCHAR(20) NOT NULL DEFAULT 'user'
      CHECK (user_type IN ('user','admin','cityadmin','superadmin'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'user_mail'
  ) THEN
    ALTER TABLE users ADD COLUMN user_mail VARCHAR(255) DEFAULT NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'user_password'
  ) THEN
    ALTER TABLE users ADD COLUMN user_password VARCHAR(255) DEFAULT NULL;
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_mail ON users(user_mail) WHERE user_mail IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_type ON users(user_type);

-- Add city column to users (for cityadmin city scope)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'city'
  ) THEN
    ALTER TABLE users ADD COLUMN city VARCHAR(255) DEFAULT NULL;
  END IF;
END;
$$;

-- Indexes on existing photos table (safe to re-run)
CREATE INDEX IF NOT EXISTS idx_photos_uploaded_at ON photos(uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_photos_user_id     ON photos(user_id);
CREATE INDEX IF NOT EXISTS idx_photos_status      ON photos(status);
CREATE INDEX IF NOT EXISTS idx_photos_coords      ON photos(latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Pothole events detected by accelerometer while driving
CREATE TABLE IF NOT EXISTS potholes (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
  device_id   VARCHAR(36),
  detected_at TIMESTAMPTZ NOT NULL,
  latitude    DOUBLE PRECISION NOT NULL,
  longitude   DOUBLE PRECISION NOT NULL,
  speed_kmh   DOUBLE PRECISION,
  peak_g      DOUBLE PRECISION,
  accuracy_m  DOUBLE PRECISION,
  uploaded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (device_id, detected_at, latitude, longitude)
);

CREATE INDEX IF NOT EXISTS idx_potholes_detected  ON potholes(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_potholes_coords    ON potholes(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_potholes_device    ON potholes(device_id);
CREATE INDEX IF NOT EXISTS idx_potholes_user      ON potholes(user_id);

-- ============================================================
-- Reference — existing tables (already in DB, do not recreate)
-- ============================================================
-- CREATE TABLE photos (
--   id serial PK, uuid varchar(36) UNIQUE,
--   user_id integer → users(id),
--   filename varchar(255), original_name varchar(255),
--   size_bytes bigint, mime_type varchar(64),
--   latitude/longitude/altitude double precision,
--   address text, photo_date timestamptz,
--   measurements jsonb,          ← stored directly here
--   device_note text,
--   uploaded_at timestamptz DEFAULT now(),
--   status varchar(50) DEFAULT 'new'
-- );
--
-- CREATE TABLE users (
--   id serial PK, device_id varchar(36) UNIQUE,
--   first_seen timestamptz, last_seen timestamptz,
--   photo_count integer DEFAULT 0
-- );
