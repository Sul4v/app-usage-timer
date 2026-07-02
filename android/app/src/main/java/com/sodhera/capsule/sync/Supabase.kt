package com.sodhera.capsule.sync

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.sodhera.capsule.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val email: String,
    val expiresAtMs: Long,
)

class SupabaseException(message: String) : Exception(message)

/**
 * Minimal client for Supabase's GoTrue (auth) and PostgREST (data) HTTP APIs.
 * Mirrors the iOS implementation; both apps talk to the same schema.
 */
object Supabase {
    private val gson = Gson()

    val isConfigured: Boolean
        get() = BuildConfig.SUPABASE_URL.isNotEmpty() && BuildConfig.SUPABASE_ANON_KEY.isNotEmpty()

    // MARK: auth

    suspend fun signUp(email: String, password: String): AuthSession =
        auth("auth/v1/signup", mapOf("email" to email, "password" to password))

    suspend fun signIn(email: String, password: String): AuthSession =
        auth("auth/v1/token?grant_type=password", mapOf("email" to email, "password" to password))

    suspend fun refresh(session: AuthSession): AuthSession =
        auth("auth/v1/token?grant_type=refresh_token", mapOf("refresh_token" to session.refreshToken))

    private suspend fun auth(path: String, body: Map<String, String>): AuthSession {
        val json = request("POST", path, gson.toJson(body), null)
        val obj = gson.fromJson(json, JsonObject::class.java)
        val user = obj.getAsJsonObject("user")
            ?: throw SupabaseException("No user in response")
        return AuthSession(
            accessToken = obj.get("access_token").asString,
            refreshToken = obj.get("refresh_token").asString,
            userId = user.get("id").asString,
            email = user.get("email")?.takeIf { !it.isJsonNull }?.asString ?: "",
            expiresAtMs = System.currentTimeMillis() + obj.get("expires_in").asLong * 1000,
        )
    }

    // MARK: data

    suspend fun upsert(table: String, rowsJson: String, session: AuthSession, onConflict: String) {
        request(
            "POST", "rest/v1/$table?on_conflict=$onConflict", rowsJson, session,
            prefer = "resolution=merge-duplicates,return=minimal",
        )
    }

    suspend fun select(table: String, query: String, session: AuthSession): String =
        request("GET", "rest/v1/$table?$query", null, session)

    // MARK: plumbing

    private suspend fun request(
        method: String,
        path: String,
        body: String?,
        session: AuthSession?,
        prefer: String? = null,
    ): String = withContext(Dispatchers.IO) {
        if (!isConfigured) throw SupabaseException("Sync isn't configured in this build.")
        val conn = URL("${BuildConfig.SUPABASE_URL.trimEnd('/')}/$path")
            .openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.setRequestProperty("apikey", BuildConfig.SUPABASE_ANON_KEY)
            conn.setRequestProperty("Content-Type", "application/json")
            val bearer = session?.accessToken ?: BuildConfig.SUPABASE_ANON_KEY
            conn.setRequestProperty("Authorization", "Bearer $bearer")
            prefer?.let { conn.setRequestProperty("Prefer", it) }
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.readText() ?: ""
            if (code !in 200..299) {
                val message = runCatching {
                    val obj = gson.fromJson(text, JsonObject::class.java)
                    (obj.get("msg") ?: obj.get("message") ?: obj.get("error_description"))?.asString
                }.getOrNull()
                throw SupabaseException(message ?: "HTTP $code: ${text.take(200)}")
            }
            text
        } finally {
            conn.disconnect()
        }
    }
}
