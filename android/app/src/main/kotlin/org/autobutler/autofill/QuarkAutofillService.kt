// cspell:words androidx
package org.autobutler.autofill

import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Quark's Android autofill service (#3600, docs/design/native-autofill-vault.md). Enabled from API 26 by
 * `@bool/quark_autofill_enabled`, and bound only by the system (`BIND_AUTOFILL_SERVICE`).
 *
 * A fill request is answered without a key and without the network: [AutofillResponses] finds the login
 * fields and either offers one suggestion that unlocks with the biometric in [AutofillUnlockActivity], or one
 * that opens Quark and fills nothing. Nothing here is decrypted, and nothing is logged but an exception's class.
 * Saving a login is #3602, so no response asks to save.
 */
@RequiresApi(Build.VERSION_CODES.O)
class QuarkAutofillService : AutofillService() {
    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        val response = try {
            request.fillContexts.lastOrNull()?.structure?.let { AutofillResponses.forRequest(this, it) }
        } catch (e: Exception) {
            Log.w(TAG, "fill request failed: ${e.javaClass.simpleName}")
            null
        }
        callback.onSuccess(response)
    }

    // No response carries SaveInfo until #3602, so the system never asks.
    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onSuccess()
    }

    private companion object {
        const val TAG = "QuarkAutofill"
    }
}
