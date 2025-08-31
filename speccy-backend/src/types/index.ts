export interface User {
  id: string;
  openai_token_hash: string;
  created_at: string;
  last_seen_at: string;
}

export interface AudioFile {
  id: string;
  user_id: string;
  content_hash: string;
  text_content: string;
  voice: string;
  model: string;
  format: string;
  speed: number;
  file_path?: string;
  file_size?: number;
  status: 'generating' | 'ready' | 'failed' | 'expired';
  created_at: string;
  expires_at: string;
}

export interface TTSRequest {
  text: string;
  voice: 'alloy' | 'echo' | 'fable' | 'onyx' | 'nova' | 'shimmer';
  model: 'tts-1' | 'tts-1-hd';
  format: 'mp3' | 'opus' | 'aac' | 'flac';
  speed?: number;
}

export interface TTSResponse {
  file_id: string;
  content_hash: string;
  status: 'generating' | 'ready' | 'failed';
  url?: string;
  expires_at: string;
}

export interface AuthRequest {
  openai_token: string;
}

export interface AuthResponse {
  user_id: string;
  session_token: string;
}

export interface FileStatusResponse {
  status: 'generating' | 'ready' | 'failed' | 'not_found';
  file_id?: string;
  expires_at?: string;
}

export interface UsageResponse {
  files_count: number;
  storage_used_mb: number;
  generated_today: number;
  last_cleanup: string;
}