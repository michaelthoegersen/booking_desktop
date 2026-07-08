-- ============================================================
-- Chat attachments: raise file size limit so normal audio files
-- (MP3 / M4A / WAV) and short videos can be uploaded.
-- Previous limit: 26214400 (25 MB) → new: 104857600 (100 MB)
-- ============================================================

UPDATE storage.buckets
   SET file_size_limit = 104857600
 WHERE id = 'chat-attachments';
