import Database from 'better-sqlite3';
import { join } from 'path';
import { existsSync, mkdirSync } from 'fs';

const DATABASE_PATH = process.env.DATABASE_PATH || './data/speccy.db';
const DATABASE_DIR = join(DATABASE_PATH, '..');

// Ensure database directory exists
if (!existsSync(DATABASE_DIR)) {
  mkdirSync(DATABASE_DIR, { recursive: true });
}

// Create database connection
export const db: Database.Database = new Database(DATABASE_PATH);

// Enable WAL mode for better concurrent access
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');
db.pragma('foreign_keys = ON');

// Close database on process exit
process.on('SIGINT', () => {
  db.close();
  process.exit(0);
});

export default db;