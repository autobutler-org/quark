/// What a file is, as far as picking a viewer goes.
///
/// This is the client's one extension table: every viewer-routing decision —
/// opening a row, a deep link, an archive entry, a thumbnail — reads it. The
/// server's `fileType` is a hint for older clients and is not consulted, so a
/// new viewer never needs a backend release (#1829).
enum FileKind {
  qdoc,
  qsheet,
  text,
  code,
  image,
  svg,
  video,
  audio,
  pdf,
  docx,
  slideshow,
  epub,
  xlsx,
  csv,
  archive,
  generic,
}

/// The lowercase extension of [name], dot included, or `''` when it has none.
String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

/// Classifies [name] by its extension.
FileKind fileKindForName(String name) =>
    _kindByExtension[fileExtension(name)] ?? FileKind.generic;

/// Image extensions the server's thumbnail endpoint can decode. Narrower than
/// [FileKind.image] on purpose: raw camera formats, BMP and TIFF are images
/// the server cannot resize, so their rows keep the plain icon.
const thumbnailImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
};

/// Image extensions `Image.memory` decodes on every platform without a server
/// round trip. Archive entries get no server conversion (#1851), so only these
/// preview from inside a zip; every other image downloads.
const clientDecodedImageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};

/// Image extensions `Image.memory` cannot decode, so the client asks the
/// server for a JPEG instead (`?format=jpeg`, #1567).
const serverConvertedImageExtensions = {
  '.heic',
  '.heif',
  '.tiff',
  '.tif',
  '.bmp',
  '.raw',
  '.cr2',
  '.cr3',
  '.nef',
  '.arw',
  '.dng',
  '.orf',
  '.rw2',
};

const _kindByExtension = {
  '.qdoc': FileKind.qdoc,
  '.qsheet': FileKind.qsheet,
  '.pdf': FileKind.pdf,
  '.docx': FileKind.docx,
  '.pptx': FileKind.slideshow,
  '.ppt': FileKind.slideshow,
  '.epub': FileKind.epub,
  // .xlsm is .xlsx with macros attached. The legacy binary .xls is not OOXML
  // and has no reader, so it stays generic (#1741).
  '.xlsx': FileKind.xlsx,
  '.xlsm': FileKind.xlsx,
  '.csv': FileKind.csv,
  // SVG is XML, not a raster codec, so it needs SvgPicture (#1806).
  '.svg': FileKind.svg,
  '.png': FileKind.image,
  '.jpg': FileKind.image,
  '.jpeg': FileKind.image,
  '.gif': FileKind.image,
  '.heic': FileKind.image,
  '.heif': FileKind.image,
  '.webp': FileKind.image,
  '.bmp': FileKind.image,
  '.tiff': FileKind.image,
  '.tif': FileKind.image,
  '.avif': FileKind.image,
  // Raw camera formats
  '.raw': FileKind.image,
  '.cr2': FileKind.image,
  '.cr3': FileKind.image,
  '.nef': FileKind.image,
  '.nrw': FileKind.image,
  '.arw': FileKind.image,
  '.srf': FileKind.image,
  '.sr2': FileKind.image,
  '.orf': FileKind.image,
  '.rw2': FileKind.image,
  '.pef': FileKind.image,
  '.dng': FileKind.image,
  '.raf': FileKind.image,
  '.rwl': FileKind.image,
  '.x3f': FileKind.image,
  '.mp3': FileKind.audio,
  '.wav': FileKind.audio,
  '.flac': FileKind.audio,
  '.aac': FileKind.audio,
  '.ogg': FileKind.audio,
  '.m4a': FileKind.audio,
  '.wma': FileKind.audio,
  '.opus': FileKind.audio,
  '.mp4': FileKind.video,
  '.m4v': FileKind.video,
  '.webm': FileKind.video,
  '.ogv': FileKind.video,
  '.avi': FileKind.video,
  '.mov': FileKind.video,
  '.mkv': FileKind.video,
  '.wmv': FileKind.video,
  '.flv': FileKind.video,
  '.3gp': FileKind.video,
  '.3g2': FileKind.video,
  '.mpeg': FileKind.video,
  '.mpg': FileKind.video,
  // MPEG transport stream, not TypeScript (.tsx is code).
  '.ts': FileKind.video,
  '.zip': FileKind.archive,
  '.rar': FileKind.archive,
  '.tar': FileKind.archive,
  '.gz': FileKind.archive,
  '.tgz': FileKind.archive,
  '.7z': FileKind.archive,
  '.txt': FileKind.text,
  '.md': FileKind.text,
  '.markdown': FileKind.text,
  '.rst': FileKind.text,
  '.log': FileKind.text,
  '.env': FileKind.text,
  '.json': FileKind.code,
  '.yaml': FileKind.code,
  '.yml': FileKind.code,
  '.toml': FileKind.code,
  '.xml': FileKind.code,
  '.ini': FileKind.code,
  '.cfg': FileKind.code,
  '.conf': FileKind.code,
  '.html': FileKind.code,
  '.htm': FileKind.code,
  '.css': FileKind.code,
  '.scss': FileKind.code,
  '.sass': FileKind.code,
  '.less': FileKind.code,
  '.js': FileKind.code,
  '.mjs': FileKind.code,
  '.cjs': FileKind.code,
  '.jsx': FileKind.code,
  '.tsx': FileKind.code,
  '.go': FileKind.code,
  '.c': FileKind.code,
  '.h': FileKind.code,
  '.cpp': FileKind.code,
  '.cc': FileKind.code,
  '.cxx': FileKind.code,
  '.hpp': FileKind.code,
  '.cs': FileKind.code,
  '.rs': FileKind.code,
  '.zig': FileKind.code,
  '.java': FileKind.code,
  '.kt': FileKind.code,
  '.kts': FileKind.code,
  '.scala': FileKind.code,
  '.groovy': FileKind.code,
  '.py': FileKind.code,
  '.rb': FileKind.code,
  '.php': FileKind.code,
  '.lua': FileKind.code,
  '.perl': FileKind.code,
  '.pl': FileKind.code,
  '.sh': FileKind.code,
  '.bash': FileKind.code,
  '.zsh': FileKind.code,
  '.fish': FileKind.code,
  '.swift': FileKind.code,
  '.dart': FileKind.code,
  '.m': FileKind.code,
  '.sql': FileKind.code,
  '.graphql': FileKind.code,
  '.gql': FileKind.code,
  '.tf': FileKind.code,
  '.hcl': FileKind.code,
  '.dockerfile': FileKind.code,
  '.makefile': FileKind.code,
  '.lisp': FileKind.code,
  '.cl': FileKind.code,
  '.scm': FileKind.code,
  '.clj': FileKind.code,
  '.cljs': FileKind.code,
  '.ex': FileKind.code,
  '.exs': FileKind.code,
  '.erl': FileKind.code,
  '.hrl': FileKind.code,
};
