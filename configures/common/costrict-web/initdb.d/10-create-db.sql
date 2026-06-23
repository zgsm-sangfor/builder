-- Create costrict_web database and enable vector extension
CREATE DATABASE costrict_db;
\c costrict_db;
CREATE EXTENSION IF NOT EXISTS vector;
GRANT ALL PRIVILEGES ON DATABASE costrict_db TO costrict;
