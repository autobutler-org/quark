// cspell:words emailaddress
package org.autobutler.autofill

import android.text.InputType

/**
 * One view of the screen being filled: the parts of `AssistStructure.ViewNode` that [LoginForm.parse] reads.
 * [AndroidFormNode] wraps a real node, and the JVM tests build these by hand. [Id] is the node's
 * `AutofillId`, null for a view that cannot be filled.
 */
interface FormNode<Id> {
    /** The view's autofill id, or null when it has none. */
    val id: Id?

    /** The app's `android:autofillHints`, empty when it set none. */
    val autofillHints: List<String>

    /** `HtmlInfo`'s attributes for a web view's input (`type`, `autocomplete`, `name`); empty otherwise. */
    val htmlAttributes: Map<String, String>

    /** The view's `android:inputType`. */
    val inputType: Int

    /** The view's resource id name (`idEntry`), if it has one. */
    val idEntry: String?

    /** The view's placeholder text, if it has one. */
    val hint: String?

    /** The web domain a browser reported for this node and what is under it, if any. */
    val webDomain: String?

    /** Whether the view takes text (`AUTOFILL_TYPE_TEXT`). */
    val isText: Boolean

    /** Whether the view is shown, its own visibility `VISIBLE`. */
    val isVisible: Boolean

    /** Whether the view can take focus. */
    val isFocusable: Boolean

    /** The views inside this one. */
    val children: List<FormNode<Id>>
}

/**
 * The login fields of one screen (#3600): the views to put a username and a password in, and the web domain
 * they were reported under.
 *
 * [webDomain] is set only when every field sits under the same reported domain. A field under another
 * domain (a cross-site frame) or under none sets [domainConflict], and the service then refuses to fill
 * (docs/design/native-autofill-vault.md, "Android phishing through `webDomain`"). A view that is not
 * visible (or sits inside one that is not) or cannot take focus is never
 * a field.
 */
class LoginForm<Id>(
    val usernames: List<Id>,
    val passwords: List<Id>,
    val webDomain: String?,
    val domainConflict: Boolean,
) {
    /** Every field, usernames first. */
    val fields: List<Id> get() = usernames + passwords

    /** Whether there is anything to fill. */
    val isEmpty: Boolean get() = usernames.isEmpty() && passwords.isEmpty()

    /** What a view is to a login form. */
    enum class Kind { USERNAME, PASSWORD }

    companion object {
        /**
         * Finds the login fields under [roots], the structure's windows. A field is classified by its
         * autofill hints first, then a web input's `autocomplete` and `type`, then its input type, and last
         * its id and placeholder. A username found only by that last guess counts only beside a password,
         * so a search box is never offered a login.
         */
        fun <Id> parse(roots: List<FormNode<Id>>): LoginForm<Id> {
            val usernames = mutableListOf<Id>()
            val guessedUsernames = mutableListOf<Pair<Id, String?>>()
            val passwords = mutableListOf<Id>()
            val domains = mutableSetOf<String?>()

            // A view inside a hidden one is hidden too.
            fun walk(node: FormNode<Id>, inherited: String?, parentShown: Boolean) {
                val domain = node.webDomain?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: inherited
                val shown = parentShown && node.isVisible
                val id = node.id
                if (id != null && node.isText && shown && node.isFocusable) {
                    classify(node)?.let { (kind, declared) ->
                        when {
                            kind == Kind.PASSWORD -> passwords += id
                            declared -> usernames += id
                            else -> guessedUsernames += id to domain
                        }
                        if (kind == Kind.PASSWORD || declared) domains += domain
                    }
                }
                node.children.forEach { walk(it, domain, shown) }
            }
            roots.forEach { walk(it, null, true) }

            // Guessed usernames with no password beside them were not fields after all.
            if (passwords.isNotEmpty()) {
                usernames += guessedUsernames.map { it.first }
                domains += guessedUsernames.map { it.second }
            }
            return LoginForm(
                usernames = usernames,
                passwords = passwords,
                webDomain = domains.singleOrNull(),
                domainConflict = domains.size > 1,
            )
        }

        /** The view's kind and whether it was declared rather than guessed, or null when it is not a login field. */
        private fun <Id> classify(node: FormNode<Id>): Pair<Kind, Boolean>? {
            if (node.autofillHints.isNotEmpty()) {
                val hints = node.autofillHints.map { it.lowercase() }
                return when {
                    hints.any { it in PASSWORD_HINTS } -> Kind.PASSWORD to true
                    hints.any { it in USERNAME_HINTS } -> Kind.USERNAME to true
                    // The app said what the field is, and it is not a login.
                    else -> null
                }
            }
            val autocomplete = node.htmlAttributes["autocomplete"]?.lowercase()?.split(' ').orEmpty()
            when {
                "new-password" in autocomplete -> return null
                "current-password" in autocomplete -> return Kind.PASSWORD to true
                autocomplete.any { it in USERNAME_HINTS } -> return Kind.USERNAME to true
            }
            when (node.htmlAttributes["type"]?.lowercase()) {
                "password" -> return Kind.PASSWORD to true
                "email" -> return Kind.USERNAME to true
                "hidden", "search", "checkbox", "radio", "submit", "button" -> return null
            }
            val inputClass = node.inputType and InputType.TYPE_MASK_CLASS
            val variation = node.inputType and InputType.TYPE_MASK_VARIATION
            if (inputClass == InputType.TYPE_CLASS_TEXT) {
                when (variation) {
                    InputType.TYPE_TEXT_VARIATION_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                    -> return Kind.PASSWORD to true
                    InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                    InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                    -> return Kind.USERNAME to false
                }
            }
            if (inputClass == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD) {
                return Kind.PASSWORD to true
            }
            val words = listOfNotNull(node.idEntry, node.hint, node.htmlAttributes["name"]).joinToString(" ").lowercase()
            return when {
                PASSWORD_WORDS.any { it in words } -> Kind.PASSWORD to false
                USERNAME_WORDS.any { it in words } -> Kind.USERNAME to false
                else -> null
            }
        }

        // View.AUTOFILL_HINT_PASSWORD, and the HTML autocomplete token Chrome passes through.
        private val PASSWORD_HINTS = setOf("password", "current-password")

        // View.AUTOFILL_HINT_USERNAME and AUTOFILL_HINT_EMAIL_ADDRESS, and their HTML tokens.
        private val USERNAME_HINTS = setOf("username", "emailaddress", "email")

        private val PASSWORD_WORDS = listOf("password", "passwd", "pwd")
        private val USERNAME_WORDS = listOf("user", "login", "email", "e-mail", "account")
    }
}
