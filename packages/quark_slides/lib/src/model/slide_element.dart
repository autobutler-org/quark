import '../format/json_fields.dart';
import 'element_frame.dart';
import 'slide_color.dart';
import 'stroke.dart';
import 'text_paragraph.dart';
import 'unset.dart';

/// Something placed on a slide: a [TextBox], [ShapeElement], [ImageElement]
/// or [LineElement], or an [UnknownElement] a newer version wrote.
///
/// Every element has an [id], unique within its presentation and stable for
/// the element's life — moving, restyling or reordering it keeps the id —
/// and a [frame] giving its position, size and rotation. Its stacking order
/// is its index in `Slide.elements`.
///
/// In `.qslide` an element is an object with a `type` discriminator:
///
/// ```json
/// {"id": "e1", "type": "shape", "kind": "ellipse",
///  "frame": {"x": 100, "y": 80, "width": 400, "height": 300},
///  "fill": "#3366FF"}
/// ```
sealed class SlideElement {
  const SlideElement({
    required this.id,
    required this.frame,
    this.extra = const {},
  });

  /// The element's stable id.
  final String id;

  /// Position, size and rotation in slide units.
  final ElementFrame frame;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The `type` discriminator written to `.qslide`.
  String get type;

  /// Returns a copy with [frame] replaced, keeping everything else.
  SlideElement withFrame(ElementFrame frame);

  /// Returns a copy with [id] replaced, as duplicating an element needs.
  SlideElement withId(String id);

  /// The element as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'id': id,
        'type': type,
        'frame': frame.toJson(),
        ..._fieldsToJson(),
      };

  JsonMap _fieldsToJson();

  /// Reads an element from its `.qslide` object at [path].
  ///
  /// An element whose `type` this version does not know — or a shape whose
  /// `kind` it does not know — reads as an [UnknownElement] that keeps the
  /// object verbatim, so a newer writer's elements survive being opened,
  /// moved and saved here.
  factory SlideElement.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final id = requireString(json, 'id', path);
    final type = requireString(json, 'type', path);
    final frame = ElementFrame.fromJson(json['frame'], '$path.frame');
    switch (type) {
      case TextBox.typeName:
        final paragraphs = optionalList(json, 'paragraphs', path);
        return TextBox(
          id: id,
          frame: frame,
          paragraphs: List.unmodifiable([
            for (var i = 0; i < paragraphs.length; i++)
              TextParagraph.fromJson(paragraphs[i], '$path.paragraphs[$i]'),
          ]),
          anchor: enumByName(json, 'anchor', TextAnchor.values, TextAnchor.top),
          autoFit: enumByName(
            json,
            'autoFit',
            TextAutoFit.values,
            TextAutoFit.grow,
          ),
          placeholder: optionalString(json, 'placeholder', path) ?? '',
          extra: unknownFields(json, TextBox._known),
        );
      case ShapeElement.typeName:
        final kind = ShapeKind.values.asNameMap()[json['kind']];
        if (kind == null) break;
        final fill = optionalString(json, 'fill', path);
        return ShapeElement(
          id: id,
          frame: frame,
          kind: kind,
          fill:
              fill == null ? null : SlideColor.parse(fill, path: '$path.fill'),
          stroke: json['stroke'] == null
              ? null
              : Stroke.fromJson(json['stroke'], '$path.stroke'),
          extra: unknownFields(json, ShapeElement._known),
        );
      case ImageElement.typeName:
        return ImageElement(
          id: id,
          frame: frame,
          source: requireString(json, 'source', path),
          altText: optionalString(json, 'altText', path) ?? '',
          fit: enumByName(json, 'fit', ImageFit.values, ImageFit.contain),
          extra: unknownFields(json, ImageElement._known),
        );
      case LineElement.typeName:
        return LineElement(
          id: id,
          frame: frame,
          stroke: json['stroke'] == null
              ? Stroke()
              : Stroke.fromJson(json['stroke'], '$path.stroke'),
          flipped: optionalBool(json, 'flipped', path, false),
          startCap: enumByName(json, 'startCap', LineCap.values, LineCap.none),
          endCap: enumByName(json, 'endCap', LineCap.values, LineCap.none),
          extra: unknownFields(json, LineElement._known),
        );
    }
    return UnknownElement(
      id: id,
      frame: frame,
      extra: unknownFields(json, UnknownElement._known),
    );
  }
}

/// Where a [TextBox]'s text sits between the top and bottom of its frame.
enum TextAnchor {
  /// Against the top edge.
  top,

  /// Centered.
  middle,

  /// Against the bottom edge.
  bottom,
}

/// What a [TextBox] does when its text is taller than its frame.
enum TextAutoFit {
  /// The frame grows taller to fit the text; it never shrinks on its own.
  grow,

  /// The frame keeps its size and the text runs past its bottom.
  fixed,

  /// The frame keeps its size and the text is drawn smaller until it fits.
  shrink,
}

/// A box of rich text: [paragraphs] of styled runs laid out inside the
/// frame, held to the [anchor] edge, and fitted as [autoFit] says.
///
/// [placeholder] is the prompt an editor shows while the box is empty —
/// "Click to add title" — and is never part of the text itself.
class TextBox extends SlideElement {
  /// Creates a text box.
  const TextBox({
    required super.id,
    required super.frame,
    this.paragraphs = const [],
    this.anchor = TextAnchor.top,
    this.autoFit = TextAutoFit.grow,
    this.placeholder = '',
    super.extra,
  });

  /// The `type` discriminator, `text`.
  static const typeName = 'text';

  static const _known = {
    'id',
    'type',
    'frame',
    'paragraphs',
    'anchor',
    'autoFit',
    'placeholder',
  };

  /// The text, one entry per paragraph.
  final List<TextParagraph> paragraphs;

  /// Where the text sits vertically in the frame.
  final TextAnchor anchor;

  /// How the box fits text taller than its frame.
  final TextAutoFit autoFit;

  /// The prompt an editor shows while the box is empty; empty for none.
  final String placeholder;

  /// The text with styling dropped, paragraphs joined by `\n`.
  String get plainText => paragraphs.map((p) => p.plainText).join('\n');

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'paragraphs': [for (final p in paragraphs) p.toJson()],
        if (anchor != TextAnchor.top) 'anchor': anchor.name,
        if (autoFit != TextAutoFit.grow) 'autoFit': autoFit.name,
        if (placeholder.isNotEmpty) 'placeholder': placeholder,
      };

  /// Returns a copy with the given fields replaced.
  TextBox copyWith({
    String? id,
    ElementFrame? frame,
    List<TextParagraph>? paragraphs,
    TextAnchor? anchor,
    TextAutoFit? autoFit,
    String? placeholder,
  }) =>
      TextBox(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        paragraphs: paragraphs ?? this.paragraphs,
        anchor: anchor ?? this.anchor,
        autoFit: autoFit ?? this.autoFit,
        placeholder: placeholder ?? this.placeholder,
        extra: extra,
      );

  @override
  TextBox withFrame(ElementFrame frame) => copyWith(frame: frame);

  @override
  TextBox withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is TextBox &&
      other.id == id &&
      other.frame == frame &&
      other.anchor == anchor &&
      other.autoFit == autoFit &&
      other.placeholder == placeholder &&
      listEquals(other.paragraphs, paragraphs) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        frame,
        Object.hashAll(paragraphs),
        anchor,
        autoFit,
        placeholder,
        jsonHash(extra),
      );
}

/// The geometric figures a [ShapeElement] can draw, each fitted to the
/// element's frame.
enum ShapeKind {
  /// A rectangle filling the frame.
  rectangle,

  /// A rectangle with rounded corners.
  roundedRectangle,

  /// An ellipse inscribed in the frame.
  ellipse,

  /// An isosceles triangle, apex at the top center.
  triangle,

  /// A diamond touching the midpoint of each edge.
  diamond,

  /// A right-pointing block arrow.
  arrow,

  /// A five-pointed star.
  star,
}

/// A filled and outlined geometric figure.
class ShapeElement extends SlideElement {
  /// Creates a shape.
  const ShapeElement({
    required super.id,
    required super.frame,
    this.kind = ShapeKind.rectangle,
    this.fill,
    this.stroke,
    super.extra,
  });

  /// The `type` discriminator, `shape`.
  static const typeName = 'shape';

  static const _known = {'id', 'type', 'frame', 'kind', 'fill', 'stroke'};

  /// Which figure to draw.
  final ShapeKind kind;

  /// The fill color, or `null` for a hollow shape.
  final SlideColor? fill;

  /// The outline, or `null` for none.
  final Stroke? stroke;

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'kind': kind.name,
        if (fill != null) 'fill': fill!.toHex(),
        if (stroke != null) 'stroke': stroke!.toJson(),
      };

  /// Returns a copy with the given fields replaced; pass `null` to clear
  /// [fill] or [stroke].
  ShapeElement copyWith({
    String? id,
    ElementFrame? frame,
    ShapeKind? kind,
    Object? fill = unset,
    Object? stroke = unset,
  }) =>
      ShapeElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        kind: kind ?? this.kind,
        fill: identical(fill, unset) ? this.fill : fill as SlideColor?,
        stroke: identical(stroke, unset) ? this.stroke : stroke as Stroke?,
        extra: extra,
      );

  @override
  ShapeElement withFrame(ElementFrame frame) => copyWith(frame: frame);

  @override
  ShapeElement withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is ShapeElement &&
      other.id == id &&
      other.frame == frame &&
      other.kind == kind &&
      other.fill == fill &&
      other.stroke == stroke &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(id, frame, kind, fill, stroke, jsonHash(extra));
}

/// How an [ImageElement]'s picture is fitted to its frame. A value this
/// version does not know reads as [contain].
enum ImageFit {
  /// Scaled to fit inside the frame, keeping its aspect ratio.
  contain,

  /// Scaled to fill the frame, keeping its aspect ratio and cropping.
  cover,

  /// Stretched to the frame exactly.
  fill,
}

/// A picture placed on the slide.
class ImageElement extends SlideElement {
  /// Creates an image element.
  const ImageElement({
    required super.id,
    required super.frame,
    required this.source,
    this.altText = '',
    this.fit = ImageFit.contain,
    super.extra,
  });

  /// The `type` discriminator, `image`.
  static const typeName = 'image';

  static const _known = {'id', 'type', 'frame', 'source', 'altText', 'fit'};

  /// An opaque reference to the picture — a file path or URL the host app
  /// resolves. The package never loads it.
  final String source;

  /// A description for screen readers; empty when none was given.
  final String altText;

  /// How the picture fits the frame.
  final ImageFit fit;

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'source': source,
        if (altText.isNotEmpty) 'altText': altText,
        if (fit != ImageFit.contain) 'fit': fit.name,
      };

  /// Returns a copy with the given fields replaced.
  ImageElement copyWith({
    String? id,
    ElementFrame? frame,
    String? source,
    String? altText,
    ImageFit? fit,
  }) =>
      ImageElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        source: source ?? this.source,
        altText: altText ?? this.altText,
        fit: fit ?? this.fit,
        extra: extra,
      );

  @override
  ImageElement withFrame(ElementFrame frame) => copyWith(frame: frame);

  @override
  ImageElement withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is ImageElement &&
      other.id == id &&
      other.frame == frame &&
      other.source == source &&
      other.altText == altText &&
      other.fit == fit &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(id, frame, source, altText, fit, jsonHash(extra));
}

/// What is drawn at an end of a [LineElement]. A value this version does
/// not know reads as [none].
enum LineCap {
  /// A plain end.
  none,

  /// An arrowhead.
  arrow,
}

/// A straight line across its frame's diagonal.
///
/// The line runs from the frame's top-left corner to its bottom-right, or
/// from bottom-left to top-right when [flipped]. A horizontal or vertical
/// line has a zero-height or zero-width frame.
class LineElement extends SlideElement {
  /// Creates a line.
  LineElement({
    required super.id,
    required super.frame,
    Stroke? stroke,
    this.flipped = false,
    this.startCap = LineCap.none,
    this.endCap = LineCap.none,
    super.extra,
  }) : stroke = stroke ?? Stroke();

  /// The `type` discriminator, `line`.
  static const typeName = 'line';

  static const _known = {
    'id',
    'type',
    'frame',
    'stroke',
    'flipped',
    'startCap',
    'endCap',
  };

  /// The line's color and width.
  final Stroke stroke;

  /// Whether the line runs bottom-left to top-right.
  final bool flipped;

  /// What is drawn at the start of the line.
  final LineCap startCap;

  /// What is drawn at the end of the line.
  final LineCap endCap;

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'stroke': stroke.toJson(),
        if (flipped) 'flipped': true,
        if (startCap != LineCap.none) 'startCap': startCap.name,
        if (endCap != LineCap.none) 'endCap': endCap.name,
      };

  /// Returns a copy with the given fields replaced.
  LineElement copyWith({
    String? id,
    ElementFrame? frame,
    Stroke? stroke,
    bool? flipped,
    LineCap? startCap,
    LineCap? endCap,
  }) =>
      LineElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        stroke: stroke ?? this.stroke,
        flipped: flipped ?? this.flipped,
        startCap: startCap ?? this.startCap,
        endCap: endCap ?? this.endCap,
        extra: extra,
      );

  @override
  LineElement withFrame(ElementFrame frame) => copyWith(frame: frame);

  @override
  LineElement withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is LineElement &&
      other.id == id &&
      other.frame == frame &&
      other.stroke == stroke &&
      other.flipped == flipped &&
      other.startCap == startCap &&
      other.endCap == endCap &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        frame,
        stroke,
        flipped,
        startCap,
        endCap,
        jsonHash(extra),
      );
}

/// An element this version cannot interpret, kept verbatim.
///
/// It still has an [id] and a [frame], so it can be moved, resized,
/// reordered, duplicated and deleted like any other element; everything
/// else about it — including its `type` — lives in [extra] and is written
/// back unchanged. A renderer draws it as a placeholder.
class UnknownElement extends SlideElement {
  /// Creates an unknown element; [extra] must hold its `type`.
  const UnknownElement({required super.id, required super.frame, super.extra});

  static const _known = {'id', 'frame'};

  @override
  String get type => extra['type'] as String;

  @override
  JsonMap _fieldsToJson() => const {};

  @override
  UnknownElement withFrame(ElementFrame frame) =>
      UnknownElement(id: id, frame: frame, extra: extra);

  @override
  UnknownElement withId(String id) =>
      UnknownElement(id: id, frame: frame, extra: extra);

  @override
  bool operator ==(Object other) =>
      other is UnknownElement &&
      other.id == id &&
      other.frame == frame &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(id, frame, jsonHash(extra));
}
