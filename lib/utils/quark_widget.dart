import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';

/// Platform-aware stand-ins for Material widgets: a Cupertino dialog or text field on iOS, and the Material one
/// everywhere else.
class QuarkWidget {
  static bool get _useCupertino =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<T?> showDialog<T>(
    BuildContext context, {
    required Widget Function(BuildContext) builder,
    bool useRootNavigator = true,
  }) {
    if (_useCupertino) {
      return showCupertinoDialog<T>(
        context: context,
        builder: builder,
        useRootNavigator: useRootNavigator,
      );
    }

    return material.showDialog<T>(
      context: context,
      builder: builder,
      useRootNavigator: useRootNavigator,
    );
  }

  static Widget alertDialog({
    Key? key,
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    bool scrollable = false,
  }) {
    if (_useCupertino) {
      return CupertinoAlertDialog(
        key: key,
        title: title,
        content: content == null ? null : _materialHost(content),
        actions: actions ?? const <Widget>[],
      );
    }

    return material.AlertDialog(
      key: key,
      title: title,
      content: content,
      actions: actions,
      scrollable: scrollable,
    );
  }

  /// Hosts [child] in a transparent [material.Material].
  ///
  /// A [CupertinoAlertDialog] puts no Material in the tree, so any Material
  /// widget in its content — a dropdown, an [material.InkWell], a list tile —
  /// trips `debugCheckHasMaterial` and the whole dialog fails to build on iOS.
  /// Callers pass the same content to both branches of [alertDialog], so the
  /// Cupertino branch has to supply the ancestor itself.
  ///
  /// Transparency keeps the dialog's own surface visible, and inheriting the
  /// ambient text style keeps Cupertino typography rather than swapping in
  /// Material's `bodyMedium`.
  static Widget _materialHost(Widget child) {
    return Builder(
      builder: (context) => material.Material(
        type: material.MaterialType.transparency,
        textStyle: DefaultTextStyle.of(context).style,
        child: child,
      ),
    );
  }

  static Widget textField({
    Key? key,
    TextEditingController? controller,
    TextInputAction? textInputAction,
    bool autofocus = false,
    bool obscureText = false,
    bool? autocorrect,
    bool enableSuggestions = true,
    int? maxLines = 1,
    int? minLines,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    bool? enabled,
    Iterable<String>? autofillHints = const <String>[],
    String? hintText,
    Widget? suffix,
  }) {
    if (_useCupertino) {
      return CupertinoTextField(
        key: key,
        controller: controller,
        textInputAction: textInputAction,
        autofocus: autofocus,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        maxLines: maxLines,
        minLines: minLines,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        inputFormatters: inputFormatters,
        enabled: enabled ?? true,
        autofillHints: autofillHints,
        placeholder: hintText ?? '',
        suffix: suffix,
      );
    }
    return material.TextField(
      key: key,
      controller: controller,
      textInputAction: textInputAction,
      autofocus: autofocus,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      enabled: enabled,
      autofillHints: autofillHints,
      // [suffix] is the trailing control on both platforms, so a password
      // field's show/hide toggle needs no platform branch at the call site.
      decoration: material.InputDecoration(
        hintText: hintText ?? '',
        suffixIcon: suffix,
      ),
    );
  }
}
