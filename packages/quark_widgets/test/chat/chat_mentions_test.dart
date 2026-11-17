import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/src/chat/chat_mentions.dart';

/// The rules of an `@mention` (#2623): what counts as one in a message, and
/// what is being typed at the caret.
void main() {
  const names = ['ada', 'ann', 'ann-marie', 'Bob'];

  List<String> found(String text) => [
    for (final m in ChatMentions.mentionsIn(text, names))
      '${text.substring(m.start, m.end)}=${m.name}',
  ];

  test('finds each member named after an @, whatever the case', () {
    expect(found('hi @ada and @BOB!'), ['@ada=ada', '@BOB=Bob']);
    expect(found('@ada'), ['@ada=ada']);
    expect(found('(@bob), thanks'), ['@bob=Bob']);
  });

  test('leaves alone what names no member', () {
    expect(found('hi @carol'), isEmpty);
    expect(found('no mention here'), isEmpty);
    expect(found('@'), isEmpty);
    expect(ChatMentions.mentionsIn('@ada', const []), isEmpty);
  });

  test('the @ has to start a word and the name has to end one', () {
    expect(found('mail ada@ada.example'), isEmpty);
    expect(found('@adam'), isEmpty);
    expect(found('@ada_'), isEmpty);
    expect(found("@ada's turn"), ['@ada=ada']);
  });

  test('the longer of two names that start alike wins', () {
    expect(found('@ann-marie and @ann'), ['@ann-marie=ann-marie', '@ann=ann']);
  });

  test('says whether one member is mentioned', () {
    expect(ChatMentions.mentions('ping @Ada', names, 'ada'), isTrue);
    expect(ChatMentions.mentions('ping @bob', names, 'ada'), isFalse);
    expect(ChatMentions.mentions('ping ada', names, 'ada'), isFalse);
  });

  group('@everyone (#4293)', () {
    final allowed = ChatMentions.withEveryone(names, allowed: true);
    final refused = ChatMentions.withEveryone(names, allowed: false);

    test('is offered first only when allowed', () {
      expect(allowed, ['everyone', ...names]);
      expect(refused, names);
      expect(ChatMentions.matching(allowed, 'e'), ['everyone']);
    });

    test('mentions every member, whatever the case', () {
      for (final name in names) {
        expect(ChatMentions.mentions('hi @everyone', allowed, name), isTrue);
      }
      expect(ChatMentions.mentions('hi @EveryOne!', allowed, 'ada'), isTrue);
      expect(ChatMentions.mentions('(@everyone)', allowed, 'ada'), isTrue);
    });

    test('keeps the word boundaries of a name', () {
      expect(ChatMentions.mentions('@everyone_else', allowed, 'ada'), isFalse);
      expect(ChatMentions.mentions('@everyone2', allowed, 'ada'), isFalse);
      expect(ChatMentions.mentions('a@everyone', allowed, 'ada'), isFalse);
      expect(ChatMentions.mentions('everyone', allowed, 'ada'), isFalse);
    });

    test('is plain text from an author without the permission', () {
      expect(ChatMentions.mentionsIn('hi @everyone', refused), isEmpty);
      expect(ChatMentions.mentions('hi @everyone', refused, 'ada'), isFalse);
      // A member named everyone from before the name was reserved is not
      // a way around the permission.
      final legacy = ChatMentions.withEveryone(const [
        'ada',
        'Everyone',
      ], allowed: false);
      expect(ChatMentions.mentions('hi @everyone', legacy, 'ada'), isFalse);
    });

    test('reaches the reader', () {
      expect(ChatMentions.reaches('everyone', 'ada'), isTrue);
      expect(ChatMentions.reaches('Ada', 'ada'), isTrue);
      expect(ChatMentions.reaches('bob', 'ada'), isFalse);
    });
  });

  test('reads the mention being typed at the caret', () {
    expect(ChatMentions.queryAt('hi @a', 5), (start: 3, query: 'a'));
    expect(ChatMentions.queryAt('@', 1), (start: 0, query: ''));
    expect(ChatMentions.queryAt('hi @ada ok', 5), (start: 3, query: 'a'));
    expect(ChatMentions.queryAt('hi @ada ', 8), isNull);
    expect(ChatMentions.queryAt('a@b', 3), isNull);
    expect(ChatMentions.queryAt('hello', 5), isNull);
    expect(ChatMentions.queryAt('@ada', 0), isNull);
  });

  test('offers the names that start with what was typed, up to a limit', () {
    expect(ChatMentions.matching(names, 'A'), ['ada', 'ann', 'ann-marie']);
    expect(ChatMentions.matching(names, ''), names);
    expect(ChatMentions.matching(names, 'an', limit: 1), ['ann']);
    expect(ChatMentions.matching(names, 'z'), isEmpty);
  });
}
