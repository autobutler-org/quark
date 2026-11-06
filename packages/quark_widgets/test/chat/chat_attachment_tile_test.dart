import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

ChatAttachmentItem _item({
  required String id,
  required String name,
  required ChatAttachmentKind kind,
  required int size,
  String? mime,
}) => ChatAttachmentItem(
  id: id,
  name: name,
  mime:
      mime ??
      switch (kind) {
        ChatAttachmentKind.image => 'image/png',
        ChatAttachmentKind.video => 'video/mp4',
        ChatAttachmentKind.file => 'application/pdf',
      },
  size: size,
  kind: kind,
);

void main() {
  testBothViewports('draws an image, a video, and a file', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: Column(
          children: [
            ChatAttachmentTile(
              item: _item(
                id: 'photo',
                name: 'cabin.png',
                kind: ChatAttachmentKind.image,
                size: 2048,
              ),
              thumbnailBuilder: (context, item) =>
                  const SizedBox(key: Key('thumb'), width: 40, height: 40),
              onOpen: () {},
            ),
            ChatAttachmentTile(
              item: _item(
                id: 'plain',
                name: 'scan.png',
                kind: ChatAttachmentKind.image,
                size: 512,
              ),
              thumbnailBuilder: (context, item) => null,
              onOpen: () {},
            ),
            ChatAttachmentTile(
              item: _item(
                id: 'clip',
                name: 'walk.mp4',
                kind: ChatAttachmentKind.video,
                size: 1024 * 1024,
              ),
              onPlay: () {},
            ),
            ChatAttachmentTile(
              item: _item(
                id: 'note',
                name: 'directions.pdf',
                kind: ChatAttachmentKind.file,
                size: 1536,
              ),
              onOpen: () {},
            ),
          ],
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('thumb')), findsOneWidget);
    expect(find.text('cabin.png'), findsOneWidget);
    expect(find.text('scan.png'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    expect(find.text('2 KiB'), findsOneWidget);
    expect(find.text('walk.mp4'), findsOneWidget);
    expect(find.text('1 MiB'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat_attachment_play_clip')),
      findsOneWidget,
    );
    expect(find.text('directions.pdf'), findsOneWidget);
    expect(find.text('1.5 KiB'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_attachment_photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_attachment_plain')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_attachment_note')), findsOneWidget);
  });

  testWidgets('taps open an image or a file and play a video', (tester) async {
    final opened = <String>[];
    final played = <String>[];
    await pumpAt(
      tester,
      Column(
        children: [
          ChatAttachmentTile(
            item: _item(
              id: 'photo',
              name: 'cabin.png',
              kind: ChatAttachmentKind.image,
              size: 10,
            ),
            thumbnailBuilder: (context, item) =>
                const SizedBox(width: 8, height: 8),
            onOpen: () => opened.add('photo'),
            onPlay: () => played.add('photo'),
          ),
          ChatAttachmentTile(
            item: _item(
              id: 'note',
              name: 'directions.pdf',
              kind: ChatAttachmentKind.file,
              size: 10,
            ),
            onOpen: () => opened.add('note'),
          ),
          ChatAttachmentTile(
            item: _item(
              id: 'clip',
              name: 'walk.mp4',
              kind: ChatAttachmentKind.video,
              size: 10,
            ),
            onOpen: () => opened.add('clip'),
            onPlay: () => played.add('clip'),
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat_attachment_photo')));
    await tester.tap(find.byKey(const ValueKey('chat_attachment_note')));
    await tester.tap(find.byKey(const ValueKey('chat_attachment_play_clip')));
    await tester.pump();

    expect(opened, ['photo', 'note']);
    expect(played, ['clip']);
  });

  testWidgets('the message list threads attachment callbacks', (tester) async {
    final opened = <(String, String)>[];
    final played = <(String, String)>[];
    final sent = DateTime(2026, 1, 2, 3, 4);
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          ChatMessageItem(
            id: 'm',
            authorId: 'ada',
            authorName: 'Ada',
            sentAt: sent,
            body: '',
            attachments: [
              _item(
                id: 'photo',
                name: 'cabin.png',
                kind: ChatAttachmentKind.image,
                size: 10,
              ),
            ],
          ),
          ChatMessageItem(
            id: 'n',
            authorId: 'ada',
            authorName: 'Ada',
            sentAt: sent.subtract(const Duration(minutes: 1)),
            body: 'caption',
            attachments: [
              _item(
                id: 'clip',
                name: 'walk.mp4',
                kind: ChatAttachmentKind.video,
                size: 10,
              ),
            ],
          ),
        ],
        onOpenAttachment: (id, item) => opened.add((id, item.id)),
        onPlayAttachment: (id, item) => played.add((id, item.id)),
        thumbnailBuilder: (context, item) =>
            const SizedBox(key: Key('thumb'), width: 8, height: 8),
      ),
    );

    expect(find.byKey(const ValueKey('message_body_m')), findsNothing);
    expect(find.text('caption'), findsOneWidget);
    expect(find.byKey(const Key('thumb')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_attachment_photo')));
    await tester.tap(find.byKey(const ValueKey('chat_attachment_play_clip')));
    await tester.pump();

    expect(opened, [('m', 'photo')]);
    expect(played, [('n', 'clip')]);
  });
}
