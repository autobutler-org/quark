import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the poll form over the open channel (#3894): a bottom sheet on a
/// phone, a dialog on a wider screen, as the calendar's event form is. Post
/// goes through [chat]'s `postPoll`; the form closes once the poll is posted
/// and stays open with the error when it isn't. Completes when it closes.
Future<void> showChatPollEditor(
  BuildContext context, {
  required ChatController chat,
}) async {
  chat.clearSaveError();
  // Not disposed: the form still rebuilds from it while it animates out.
  final draft = ValueNotifier(const ChatPollDraft());
  Widget form(BuildContext ctx) => ListenableBuilder(
    listenable: Listenable.merge([chat, draft]),
    builder: (ctx, _) => QuarkPollEditor(
      draft: draft.value,
      onChanged: (next) => draft.value = next,
      isSaving: chat.isSaving,
      saveError: chat.saveError == null
          ? null
          : Errors.message(chat.saveError, 'post the poll'),
      onSave: draft.value.isComplete && !chat.isSaving
          ? () async {
              if (await chat.postPoll(draft.value) && ctx.mounted) {
                Navigator.of(ctx).pop();
              }
            }
          : null,
      onCancel: () => Navigator.of(ctx).pop(),
    ),
  );
  if (MediaQuery.sizeOf(context).width < QuarkBarChip.compactBreakpoint) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        // The keyboard pushes the form up rather than covering Post.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FractionallySizedBox(heightFactor: 0.92, child: form(ctx)),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
          child: form(ctx),
        ),
      ),
    );
  }
}
