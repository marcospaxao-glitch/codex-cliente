package com.otclient

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper

// CODEX: reinicia o jogo depois de uma atualizacao. Roda num processo separado
// (":reiniciar"): fecha o processo antigo do jogo e abre o jogo de novo.
class CodexReiniciar : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pid = intent.getIntExtra("pid", -1)
        if (pid > 0) android.os.Process.killProcess(pid)
        Handler(Looper.getMainLooper()).postDelayed({
            val abrir = packageManager.getLaunchIntentForPackage(packageName)
            if (abrir != null) {
                abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                startActivity(abrir)
            }
            finish()
            Runtime.getRuntime().exit(0)
        }, 500)
    }
}
