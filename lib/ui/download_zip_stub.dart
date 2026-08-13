/// Stub for non-web platforms — desktop writes directly to disk.
void platformDownloadZipFile(String archiveName, Map<String, String> files) {
  // No-op: all outputs already exist in filesystem (FileOutput).
}
