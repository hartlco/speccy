"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.db = void 0;
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const path_1 = require("path");
const fs_1 = require("fs");
const DATABASE_PATH = process.env.DATABASE_PATH || './data/speccy.db';
const DATABASE_DIR = (0, path_1.join)(DATABASE_PATH, '..');
// Ensure database directory exists
if (!(0, fs_1.existsSync)(DATABASE_DIR)) {
    (0, fs_1.mkdirSync)(DATABASE_DIR, { recursive: true });
}
// Create database connection
exports.db = new better_sqlite3_1.default(DATABASE_PATH);
// Enable WAL mode for better concurrent access
exports.db.pragma('journal_mode = WAL');
exports.db.pragma('synchronous = NORMAL');
exports.db.pragma('foreign_keys = ON');
// Close database on process exit
process.on('SIGINT', () => {
    exports.db.close();
    process.exit(0);
});
exports.default = exports.db;
//# sourceMappingURL=connection.js.map