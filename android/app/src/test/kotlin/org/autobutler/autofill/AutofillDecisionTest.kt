// cspell:words Fexample
package org.autobutler.autofill

import android.text.InputType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * What a fill request is answered with before any key is used (#3600), and above all the phishing
 * countermeasures: a web domain counts only from a trusted browser, only when it is one domain, and a
 * doubt never fills (docs/design/native-autofill-vault.md, "Android phishing through `webDomain`").
 */
class AutofillDecisionTest {
    private val password = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD

    private fun form(domain: String?) = LoginForm.parse(
        listOf(
            FakeNode(
                webDomain = domain,
                children = listOf(FakeNode("u", autofillHints = listOf("username")), FakeNode("p", inputType = password)),
            ),
        ),
    )

    private fun plan(
        form: LoginForm<String>,
        trusted: Boolean = true,
        hasVault: Boolean = true,
        requester: String = "com.android.chrome",
    ) = AutofillDecision.plan(form, requester, "org.autobutler.quark", { trusted }, { hasVault })

    @Test
    fun `a trusted browser on a known site with a stored vault asks to unlock`() {
        val result = plan(form("Accounts.Bank.Example")) as FillPlan.Unlock
        assertEquals("accounts.bank.example", result.host)
        assertEquals("com.android.chrome", result.requester)
        assertEquals(listOf("u", "p"), result.form.fields)
    }

    @Test
    fun `an app that claims a web domain is not believed`() {
        var read = false
        val result = AutofillDecision.plan(form("bank.example"), "com.evil.app", "org.autobutler.quark", { false }, {
            read = true
            true
        })
        assertEquals(FillPlan.OpenQuark(listOf("u", "p"), OpenQuarkReason.APP), result)
        assertFalse("an untrusted app never reaches the vault", read)
    }

    @Test
    fun `a native app matches nothing until #3601`() {
        assertEquals(OpenQuarkReason.APP, (plan(form(null), trusted = false) as FillPlan.OpenQuark).reason)
    }

    @Test
    fun `a browser that names no site is refused`() {
        assertEquals(OpenQuarkReason.UNSURE_SITE, (plan(form(null)) as FillPlan.OpenQuark).reason)
    }

    @Test
    fun `a browser whose domain has no host is refused`() {
        assertEquals(OpenQuarkReason.UNSURE_SITE, (plan(form("bank%2Fexample")) as FillPlan.OpenQuark).reason)
    }

    @Test
    fun `fields under two sites are refused`() {
        val conflicting = LoginForm.parse(
            listOf(
                FakeNode(webDomain = "bank.example", children = listOf(FakeNode("u", autofillHints = listOf("username")))),
                FakeNode(webDomain = "evil.example", children = listOf(FakeNode("p", inputType = password))),
            ),
        )
        assertEquals(OpenQuarkReason.UNSURE_SITE, (plan(conflicting) as FillPlan.OpenQuark).reason)
    }

    @Test
    fun `no stored vault opens Quark`() {
        assertEquals(OpenQuarkReason.LOCKED, (plan(form("bank.example"), hasVault = false) as FillPlan.OpenQuark).reason)
    }

    @Test
    fun `no login fields and Quark's own screens get nothing`() {
        assertEquals(FillPlan.Ignore, plan(LoginForm.parse(listOf(FakeNode("search")))))
        assertEquals(FillPlan.Ignore, plan(form("bank.example"), requester = "org.autobutler.quark"))
    }
}
