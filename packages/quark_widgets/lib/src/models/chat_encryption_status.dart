/// Where the open chat channel's encryption stands, when it needs saying.
///
/// `QuarkEncryptionNotice` draws one of these above the composer; a channel
/// with nothing to say has no status at all. Listed most urgent first: a
/// caller with more than one picks the earliest.
enum ChatEncryptionStatus {
  /// The user can read the channel but has not been given its current key,
  /// so they can't send yet. Clears itself once a member shares it.
  waitingForKey,

  /// The channel's current key was made by someone whose signature could not
  /// be checked. Messages still work.
  unverifiedKey,

  /// Some earlier messages were locked with a key the user was never given,
  /// so they stay hidden. New messages work.
  unreadableHistory,
}
