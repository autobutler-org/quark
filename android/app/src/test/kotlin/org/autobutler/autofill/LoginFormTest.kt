// cspell:words unfocusable
package org.autobutler.autofill

import android.text.InputType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A hand-built view for [LoginForm.parse]. */
data class FakeNode(
    override val id: String? = null,
    override val autofillHints: List<String> = emptyList(),
    override val htmlAttributes: Map<String, String> = emptyMap(),
    override val inputType: Int = InputType.TYPE_CLASS_TEXT,
    override val idEntry: String? = null,
    override val hint: String? = null,
    override val webDomain: String? = null,
    override val isText: Boolean = id != null,
    override val isVisible: Boolean = true,
    override val isFocusable: Boolean = id != null,
    override val children: List<FormNode<String>> = emptyList(),
) : FormNode<String>

/** Which views of a screen are its login fields, and which site they were reported under (#3600). */
class LoginFormTest {
    private val password = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD

    private fun parse(vararg nodes: FakeNode, domain: String? = null) =
        LoginForm.parse(listOf(FakeNode(webDomain = domain, children = nodes.toList())))

    @Test
    fun `autofill hints name the fields`() {
        val form = parse(
            FakeNode("u", autofillHints = listOf("username")),
            FakeNode("p", autofillHints = listOf("password")),
        )
        assertEquals(listOf("u"), form.usernames)
        assertEquals(listOf("p"), form.passwords)
    }

    @Test
    fun `a hint that is not a login wins over a password input type`() {
        val form = parse(FakeNode("x", autofillHints = listOf("creditCardNumber"), inputType = password))
        assertTrue(form.isEmpty)
    }

    @Test
    fun `web inputs are read from autocomplete and type`() {
        val form = parse(
            FakeNode("u", htmlAttributes = mapOf("autocomplete" to "section-a username")),
            FakeNode("p", htmlAttributes = mapOf("type" to "password")),
            FakeNode("n", htmlAttributes = mapOf("type" to "password", "autocomplete" to "new-password")),
            domain = "bank.example",
        )
        assertEquals(listOf("u"), form.usernames)
        assertEquals(listOf("p"), form.passwords)
        assertEquals("bank.example", form.webDomain)
    }

    @Test
    fun `input types and ids are the fallback`() {
        val form = parse(
            FakeNode("u", idEntry = "login_email"),
            FakeNode("p", inputType = password),
        )
        assertEquals(listOf("u"), form.usernames)
        assertEquals(listOf("p"), form.passwords)
    }

    @Test
    fun `a guessed username with no password beside it is not a field`() {
        assertTrue(parse(FakeNode("search", hint = "Search users")).isEmpty)
    }

    @Test
    fun `hidden and unfocusable views are never filled`() {
        val form = parse(
            FakeNode("hidden", inputType = password, isVisible = false),
            FakeNode("still", inputType = password, isFocusable = false),
            FakeNode(isVisible = false, children = listOf(FakeNode("inside", inputType = password))),
        )
        assertTrue(form.isEmpty)
    }

    @Test
    fun `the domain is inherited from the node a browser put it on`() {
        val form = parse(FakeNode("p", inputType = password), domain = "Accounts.Bank.Example")
        assertEquals("accounts.bank.example", form.webDomain)
        assertFalse(form.domainConflict)
    }

    @Test
    fun `fields under two domains conflict and name none`() {
        val form = LoginForm.parse(
            listOf(
                FakeNode(webDomain = "bank.example", children = listOf(FakeNode("u", autofillHints = listOf("username")))),
                FakeNode(webDomain = "evil.example", children = listOf(FakeNode("p", inputType = password))),
            ),
        )
        assertTrue(form.domainConflict)
        assertNull(form.webDomain)
    }

    @Test
    fun `a field under no domain beside one under a domain conflicts`() {
        val form = LoginForm.parse(
            listOf(
                FakeNode(webDomain = "bank.example", children = listOf(FakeNode("p", inputType = password))),
                FakeNode("u", autofillHints = listOf("username")),
            ),
        )
        assertTrue(form.domainConflict)
    }

    @Test
    fun `a domain on a view that is not a field does not count`() {
        val form = parse(
            FakeNode("p", inputType = password),
            FakeNode(webDomain = "ads.example", children = listOf(FakeNode("other"))),
            domain = "bank.example",
        )
        assertEquals("bank.example", form.webDomain)
        assertFalse(form.domainConflict)
    }
}
