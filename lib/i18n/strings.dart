/// String terpusat — D10: Inggris primary, struktur siap i18n.
class Strings {
  const Strings._();

  static const appTitle = 'pdflow';
  static const tagline = 'PDF → Markdown, on your machine';
  static const themeToggle = 'Theme';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const themeSystem = 'System';
  static const heroHeadline = 'Turn documents into clean markdown';
  static const heroSub = 'Fast, private, and fully offline. Drop your PDFs and get '
      'structured markdown — headings, paragraphs and lists, ready for reading '
      'or feeding your AI tools.';
  static const dropHere = 'Drop your PDFs here';
  static const dropSub = 'or';
  static const pickFile = 'Choose PDF files';
  static const pickFileSingular = 'Choose a PDF file';
  static const addFiles = 'Add files';
  static const convert = 'Convert';
  static const convertAll = 'Convert all';
  static const cancel = 'Cancel';
  static const reset = 'Start over';
  static const removeFile = 'Remove';
  static const pagesLabel = 'pages';
  static const sizeLabel = 'Size';
  static const converting = 'Converting';
  static const phaseReading = 'Reading pages…';
  static const phaseConverting = 'Converting page %d of %d';
  static const done = 'Done';
  static const openOutput = 'Open folder';
  static const download = 'Download';
  static const downloadStarted = 'Download started';
  static const copyPath = 'Copy path';
  static const copied = 'Path copied';
  static const convertAnother = 'Convert another';
  static const clearAll = 'Clear all';
  static const filesDone = '%d of %d converted';
  static const fileQueued = 'Queued';
  static const fileRunning = 'Converting…';
  static const fileFailed = 'Failed';
  static const fileCancelled = 'Cancelled';
  static const fileDone = 'Done';
  static const previewTitle = 'Preview';
  static const previewRawTitle = 'Raw markdown';
  static const showRendered = 'Rendered';
  static const showRaw = 'Raw';
  static const statsHeading = 'Headings';
  static const statsParagraphs = 'Paragraphs';
  static const statsListItems = 'List items';
  static const statsTime = 'Elapsed';
  static const statsPagesPerSec = 'Pages/sec';
  static const statsBodyFont = 'Body font';
  static const warningFailedPages =
      '%d page(s) failed to extract and were skipped.';
  static const errorCorrupt = 'Could not open the PDF. The file may be corrupt '
      'or not a valid PDF.';
  static const errorEncrypted = 'This PDF is password-protected, which is not '
      'supported.';
  static const errorNoText = 'No text could be extracted. This looks like a '
      'scanned document (OCR is not supported).';
  static const errorGeneric = 'Something went wrong: %s';
  static const pickFileFilterName = 'PDF files';
  static const overwriteTitle = 'Overwrite existing files?';
  static const overwriteBody = '%d file(s) already have a .md output. '
      'Continue and replace them?';
  static const overwriteConfirm = 'Overwrite all';
  static const featureFast = 'Fast';
  static const featureFastSub = 'Hundreds of pages in seconds';
  static const featureOffline = 'Private';
  static const featureOfflineSub = 'Runs 100% on your machine';
  static const featureClean = 'Clean structure';
  static const featureCleanSub = 'Headings, paragraphs, lists';
}
