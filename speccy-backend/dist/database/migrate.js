"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.runMigrations = runMigrations;
const connection_1 = __importDefault(require("./connection"));
const migrations = [
    // Migration 1: Create initial tables
    `
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      openai_token_hash TEXT UNIQUE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      last_seen_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS audio_files (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      text_content TEXT NOT NULL,
      voice TEXT NOT NULL,
      model TEXT NOT NULL,
      format TEXT NOT NULL,
      speed REAL NOT NULL DEFAULT 1.0,
      file_name TEXT,
      file_size INTEGER,
      status TEXT NOT NULL DEFAULT 'generating',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      expires_at DATETIME NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_audio_files_user_hash ON audio_files(user_id, content_hash);
    CREATE INDEX IF NOT EXISTS idx_audio_files_expires ON audio_files(expires_at);
    CREATE INDEX IF NOT EXISTS idx_audio_files_status ON audio_files(status);
    CREATE INDEX IF NOT EXISTS idx_users_token_hash ON users(openai_token_hash);
  `,
    // Migration 2: Add playback states table
    `
    CREATE TABLE IF NOT EXISTS playback_states (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      document_id TEXT NOT NULL,
      title TEXT NOT NULL,
      text_content TEXT NOT NULL,
      language_code TEXT,
      resume_key TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0.0,
      is_playing BOOLEAN NOT NULL DEFAULT 0,
      is_paused BOOLEAN NOT NULL DEFAULT 0,
      is_loading BOOLEAN NOT NULL DEFAULT 0,
      current_title TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(user_id, document_id) ON CONFLICT REPLACE
    );

    CREATE INDEX IF NOT EXISTS idx_playback_states_user_id ON playback_states(user_id);
    CREATE INDEX IF NOT EXISTS idx_playback_states_document_id ON playback_states(document_id);
    CREATE INDEX IF NOT EXISTS idx_playback_states_updated_at ON playback_states(updated_at);
  `,
];
function runMigrations() {
    console.log('🚀 Running database migrations...');
    // Create migrations table
    connection_1.default.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      migration_index INTEGER UNIQUE NOT NULL,
      executed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);
    const getExecutedMigrations = connection_1.default.prepare('SELECT migration_index FROM migrations ORDER BY migration_index');
    const insertMigration = connection_1.default.prepare('INSERT INTO migrations (migration_index) VALUES (?)');
    const executedMigrations = new Set(getExecutedMigrations.all().map((row) => row.migration_index));
    migrations.forEach((migration, index) => {
        if (!executedMigrations.has(index)) {
            console.log(`  ➡️  Running migration ${index + 1}...`);
            // Execute migration in transaction
            const transaction = connection_1.default.transaction(() => {
                connection_1.default.exec(migration);
                insertMigration.run(index);
            });
            transaction();
            console.log(`  ✅ Migration ${index + 1} completed`);
        }
        else {
            console.log(`  ⏭️  Migration ${index + 1} already executed`);
        }
    });
    console.log('✨ All migrations completed successfully!');
}
// Run migrations if this file is executed directly
if (require.main === module) {
    runMigrations();
}
//# sourceMappingURL=migrate.js.map