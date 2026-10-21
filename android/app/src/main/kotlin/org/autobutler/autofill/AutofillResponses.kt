// cspell:words androidx
package org.autobutler.autofill

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import org.autobutler.R
import java.util.concurrent.atomic.AtomicInteger

/** A real `AssistStructure.ViewNode` as a [FormNode]. */
@RequiresApi(Build.VERSION_CODES.O)
class AndroidFormNode(private val node: AssistStructure.ViewNode) : FormNode<AutofillId> {
    override val id: AutofillId? get() = node.autofillId
    override val autofillHints: List<String> get() = node.autofillHints?.toList().orEmpty()
    override val htmlAttributes: Map<String, String>
        get() = node.htmlInfo?.attributes.orEmpty().associate { it.first.lowercase() to it.second }
    override val inputType: Int get() = node.inputType
    override val idEntry: String? get() = node.idEntry
    override val hint: String? get() = node.hint
    override val webDomain: String? get() = node.webDomain
    override val isText: Boolean get() = node.autofillType == View.AUTOFILL_TYPE_TEXT
    override val isVisible: Boolean get() = node.visibility == View.VISIBLE
    override val isFocusable: Boolean get() = node.isFocusable
    override val children: List<FormNode<AutofillId>>
        get() = (0 until node.childCount).map { AndroidFormNode(node.getChildAt(it)) }

    companion object {
        /** The root view of each of [structure]'s windows. */
        fun roots(structure: AssistStructure): List<FormNode<AutofillId>> =
            (0 until structure.windowNodeCount).map { AndroidFormNode(structure.getWindowNodeAt(it).rootViewNode) }
    }
}

/**
 * Turns an `AssistStructure` into the service's answer (#3600): the [FillPlan] for it, and the
 * `FillResponse`s for each plan and for the logins the unlock screen found. The service and
 * [AutofillUnlockActivity] both plan through here, so the unlock screen decides again from the structure
 * the system hands it rather than from anything passed along.
 *
 * Suggestions show a title and a line under it, never a password: a login's name and username, or what to do.
 */
@RequiresApi(Build.VERSION_CODES.O)
object AutofillResponses {
    private val requestCodes = AtomicInteger()

    /** The plan for [structure], asked of [context]'s package. */
    fun plan(context: Context, structure: AssistStructure): FillPlan<AutofillId> {
        val requester = structure.activityComponent.packageName
        return AutofillDecision.plan(
            form = LoginForm.parse(AndroidFormNode.roots(structure)),
            requester = requester,
            ownPackage = context.packageName,
            isTrustedBrowser = { TrustedBrowsers.isTrusted(requester, signers(context.packageManager, requester)) },
            hasVault = { store(context).load() != null },
        )
    }

    /** The stored vault in [context]'s `noBackupFilesDir`. */
    fun store(context: Context): AutofillStore = DiskAutofillStore(context.noBackupFilesDir)

    /** The response to a fill request: null to offer nothing. */
    fun forRequest(context: Context, structure: AssistStructure): FillResponse? =
        when (val plan = plan(context, structure)) {
            FillPlan.Ignore -> null
            is FillPlan.OpenQuark -> {
                val views = views(context, context.getString(R.string.autofill_title), openQuarkText(context, plan.reason))
                val dataset = Dataset.Builder().apply {
                    // No value: the suggestion only opens Quark, and the system fills nothing.
                    @Suppress("DEPRECATION")
                    plan.fields.forEach { setValue(it, null, views) }
                    setAuthentication(openQuarkSender(context))
                }.build()
                FillResponse.Builder().addDataset(dataset).build()
            }
            is FillPlan.Unlock -> FillResponse.Builder()
                .setAuthentication(
                    plan.form.fields.toTypedArray(),
                    unlockSender(context),
                    views(
                        context,
                        context.getString(R.string.autofill_title),
                        context.getString(R.string.autofill_unlock, plan.host),
                    ),
                )
                .build()
        }

    /**
     * One suggestion per login in [credentials], each filling [form]'s usernames and passwords, or null when
     * none of them has anything to put in its fields.
     */
    fun forCredentials(context: Context, form: LoginForm<AutofillId>, host: String, credentials: List<Credential>): FillResponse? {
        val datasets = credentials.mapNotNull { credential ->
            val values = form.usernames.filter { credential.username.isNotEmpty() }.map { it to credential.username } +
                form.passwords.filter { credential.password.isNotEmpty() }.map { it to credential.password }
            if (values.isEmpty()) return@mapNotNull null
            val views = views(context, credential.name.ifEmpty { host }, credential.username)
            Dataset.Builder().apply {
                @Suppress("DEPRECATION")
                values.forEach { (id, value) -> setValue(id, AutofillValue.forText(value), views) }
            }.build()
        }
        if (datasets.isEmpty()) return null
        return FillResponse.Builder().apply { datasets.forEach { addDataset(it) } }.build()
    }

    /** What the "Open Quark" suggestion says for [reason]. */
    fun openQuarkText(context: Context, reason: OpenQuarkReason): String = context.getString(
        when (reason) {
            OpenQuarkReason.LOCKED -> R.string.autofill_locked
            OpenQuarkReason.APP -> R.string.autofill_app_unsupported
            OpenQuarkReason.UNSURE_SITE -> R.string.autofill_unsure_site
        },
    )

    /** An intent that opens Quark in a task of its own. */
    fun openQuarkIntent(context: Context): Intent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun openQuarkSender(context: Context): IntentSender? = openQuarkIntent(context)?.let {
        PendingIntent.getActivity(context, requestCodes.incrementAndGet(), it, PendingIntent.FLAG_IMMUTABLE).intentSender
    }

    private fun unlockSender(context: Context): IntentSender {
        // The system adds the structure to the intent as it launches it, so the intent has to be mutable.
        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getActivity(
            context,
            requestCodes.incrementAndGet(),
            Intent(context, AutofillUnlockActivity::class.java),
            PendingIntent.FLAG_CANCEL_CURRENT or mutable,
        ).intentSender
    }

    private fun views(context: Context, title: String, subtitle: String) =
        RemoteViews(context.packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_item_title, title)
            setTextViewText(R.id.autofill_item_subtitle, subtitle)
        }

    /** The certificates [packageName] is signed with now, or none when it is not installed or not visible. */
    private fun signers(packageManager: PackageManager, packageName: String): List<ByteArray> = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners.orEmpty().map { it.toByteArray() }
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                .signatures.orEmpty().map { it.toByteArray() }
        }
    } catch (_: PackageManager.NameNotFoundException) {
        emptyList()
    }
}
