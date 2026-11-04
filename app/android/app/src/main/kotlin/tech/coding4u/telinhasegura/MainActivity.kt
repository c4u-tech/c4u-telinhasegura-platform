package tech.coding4u.telinhasegura

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        asSuggestion(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        asSuggestion(intent)
        super.onNewIntent(intent)
    }

    // A shared text becomes the telinhasegura://sugerir deep link, so the
    // Flutter router opens the suggestion screen; the Dart side finds the
    // link inside the text. The text is capped to keep the URI small.
    private fun asSuggestion(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = (intent.getStringExtra(Intent.EXTRA_TEXT) ?: "").take(2048)
        intent.action = Intent.ACTION_VIEW
        intent.data = Uri.Builder()
            .scheme("telinhasegura")
            .authority("sugerir")
            .appendQueryParameter("texto", text)
            .build()
    }
}
