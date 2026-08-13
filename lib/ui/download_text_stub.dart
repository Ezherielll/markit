/// Stub for non-web platforms — desktop writes directly to disk.
void platformDownloadTextFile(String fileName, String content) {
  // No-op: output already exists in filesystem (FileOutput).
}
