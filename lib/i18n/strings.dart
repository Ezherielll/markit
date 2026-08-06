/// String terpusat — D10: Inggris primary, struktur siap i18n.
class Strings {
  const Strings._();

  static const appTitle = 'MarkIt';
  static const tagline = 'Documents → Markdown, on your machine';
  static const headerSubtitle = 'Convert documents into structured Markdown';
  static const statusReady = 'Ready to process files';  static const statusFilesLoaded = '%d files loaded';
  static const statusProcessing = 'Processing %d documents';
  static const statusConverted = '%d converted';
  static const statusBatchComplete = 'Batch conversion complete';
  static const settingsTooltip = 'Settings — coming soon';
  static const themeToggle = 'Theme';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const themeSystem = 'System';
  static const heroHeadline = 'Turn documents into clean markdown';
  static const heroSub = 'Fast, private, and fully offline. Drop your documents '
      '— PDFs, DOCX, spreadsheets and more — get structured markdown, ready '
      'for reading or feeding your AI tools.';
  static const dropHere = 'Drop your files here';
  static const dropSub = 'or';
  static const dropCompact = 'Drop files here or choose files';
  static const dropCompactSub = 'Multiple files supported · PDF, DOCX, TXT & more';
  static const pickFile = 'Choose files';
  static const pickFileSingular = 'Choose a file';
  static const addFiles = 'Add files';
  static const convert = 'Convert';
  static const viewerEmptyTitle = 'Your document preview will appear here';
  static const viewerEmptySub =
      'Add files to convert them into clean Markdown. The result will be '
      'rendered here as a readable document.';
  static const sidebarTitle = 'Workspace';
  static const sidebarFiles = 'Files';
  static const warnLargeBatch =
      '%d files in one batch — memory usage will be high. Consider converting in smaller groups.';
  static const warnLargePages =
      '"%s" has %d pages — large documents may take longer and use more memory.';
  static const convertAll = 'Convert all';
  static const convertAllShort = 'Convert';
  static const cancel = 'Cancel';
  static const reset = 'Start over';
  static const removeFile = 'Remove';
  static const pagesLabel = 'pages';
  static const sizeLabel = 'Size';
  static const converting = 'Converting';
  static const phaseReading = 'Reading pages…';
  static const phaseConverting = 'Converting page %d of %d';
  static const phaseReadingShort = 'Reading';
  static const phaseConvertingShort = 'Converting';
  static const pageOf = '%d of %d pages';
  static const done = 'Done';
  static const openOutput = 'Open folder';
  static const download = 'Download';
  static const downloadStarted = 'Download started';
  static const downloadAll = 'Download all';
  static const downloadAllZip = 'Download all as ZIP';
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
  static const previewTruncated =
      'Preview truncated for performance — download for the full content.';
  static const showRendered = 'Rendered';
  static const showRaw = 'Raw';
  static const statsHeading = 'Headings';
  static const statsParagraphs = 'Paragraphs';
  static const statsListItems = 'List items';
  static const statsRows = 'Rows';
  static const statsTime = 'Elapsed';
  static const statsPagesPerSec = 'Pages/sec';
  static const statsBodyFont = 'Body font';
  static const warningFailedPages =
      '%d page(s) failed to extract and were skipped.';
  static const urlNotSupported =
      'Links and URLs are not supported — MarkIt runs 100% offline. '
      'Please choose a local file instead.';
  static const dropNotSupported =
      'Drag & drop of files is not available in the browser — '
      'use the "Choose files" button instead.';
  static const dropNoFiles = 'No readable files found in this drop.';
  static const errorCorrupt = 'Could not open the file. It may be corrupt '
      'or not a supported format.';
  static const errorEncrypted = 'This PDF is password-protected, which is not '
      'supported.';
  static const errorNoText = 'No text could be extracted. This looks like a '
      'scanned document (OCR is not supported).';
  static const errorUnsupported = 'This file type is not supported yet '
      '(roadmap: DOCX/XLSX/PPTX/EPUB/ZIP/images/audio).';
  static const errorGeneric = 'Something went wrong: %s';
  static const pickFileFilterName = 'All supported files';
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

  // About page.
  static const back = 'Back';
  static const aboutTooltip = 'About MarkIt';
  static const aboutTitle = 'About MarkIt';
  static const aboutHero = 'Your documents, converted to clean, reusable text.';
  static const aboutIntro =
      'MarkIt turns your documents — PDFs, text files, spreadsheets, web '
      'pages, and more — into Markdown. Markdown is a clean, simple text '
      'format that is easy to read, copy, and reuse anywhere: notes, docs, '
      'or even as input for AI tools.';
  static const aboutHowTitle = 'How it works';
  static const aboutHowSub = 'Three simple steps — no account, no setup.';
  static const aboutStep1Title = 'Add your files';
  static const aboutStep1Sub =
      'Drag & drop them anywhere on the page, or click "Choose files" and '
      'pick as many as you like.';
  static const aboutStep2Title = 'Click "Convert"';
  static const aboutStep2Sub =
      'MarkIt processes your files on your device — quickly, and you can '
      'watch the progress of each file.';
  static const aboutStep3Title = 'Preview & download';
  static const aboutStep3Sub =
      'Check the result as a clean document, then download the Markdown '
      'file. Batch output can be downloaded as a ZIP.';
  static const aboutFormatsTitle = 'Supported formats';
  static const aboutFormatsSub =
      'PDF · TXT · Markdown · CSV · JSON · XML · HTML';
  static const aboutFormatsMore =
      'More formats are on the way — DOCX, XLSX, PPTX, EPUB, and more.';
  static const aboutPrivacyTitle = '100% private & offline';
  static const aboutPrivacySub =
      'Your files never leave your device. There are no uploads, no cloud, '
      'no accounts, and no tracking — everything runs locally, right in '
      'your browser. Even your internet can be turned off.';
  static const aboutFaqTitle = 'Frequently asked questions';
  static const aboutFaq1Q = 'Are my files uploaded anywhere?';
  static const aboutFaq1A =
      'No. Every conversion happens on your own device. Nothing is sent '
      'over the internet.';
  static const aboutFaq2Q = 'Does it work offline?';
  static const aboutFaq2A =
      'Yes — MarkIt is fully offline. The whole app (including the engine) '
      'is loaded once and works without a connection.';
  static const aboutFaq3Q = 'Why does the preview look different from the original?';
  static const aboutFaq3A =
      'MarkIt converts the content into structured text (headings, '
      'paragraphs, lists, tables). Visual design — colors, fonts, page '
      'layout — is intentionally simplified so the text is clean and '
      'portable.';
  static const aboutFaq4Q = 'Can I convert many files at once?';
  static const aboutFaq4A =
      'Yes. Add a whole folder of files, convert them all in one batch, '
      'and download the results individually or as a single ZIP.';
  static const aboutFooter = 'Made with care — 100% local, 100% yours.';
  static const aboutViewSource = 'View source on GitHub';
}
