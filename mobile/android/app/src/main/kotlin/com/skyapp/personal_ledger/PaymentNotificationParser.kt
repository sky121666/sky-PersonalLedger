package com.skyapp.personal_ledger

import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.min

object PaymentNotificationParser {
    private val amountPattern = Regex("""(?:¥|￥)?\s*(\d+(?:\.\d{1,2})?)\s*(?:元)?""")

    fun sourceId(packageName: String): String? {
        return when (packageName) {
            "com.tencent.mm" -> "wechat"
            "com.eg.android.AlipayGphone" -> "alipay"
            "com.unionpay" -> "unionpay"
            else -> if (packageName.contains("bank", ignoreCase = true) ||
                packageName.contains("cmb", ignoreCase = true) ||
                packageName.contains("icbc", ignoreCase = true) ||
                packageName.contains("ccb", ignoreCase = true)
            ) {
                "bank"
            } else {
                null
            }
        }
    }

    fun parse(
        packageName: String,
        title: String,
        text: String,
        postedAtMillis: Long,
    ): JSONObject? {
        val source = sourceId(packageName) ?: return null
        val combined = listOf(title, text).joinToString(" ").trim()
        if (combined.isBlank()) {
            return null
        }

        val amount = findAmount(combined) ?: return null
        val type = inferType(combined) ?: return null
        val merchant = inferMerchant(title, text, amount).ifBlank { sourceName(source) }
        val hash = sha1("$packageName|$postedAtMillis|$combined")
        val confidence = confidenceFor(source, combined)

        return JSONObject()
            .put("id", "android-$hash")
            .put("source", "android_notification")
            .put("source_name", sourceName(source))
            .put("source_id", source)
            .put("type", type)
            .put("amount", amount)
            .put("merchant", merchant)
            .put("occurred_at", postedAtMillis)
            .put("confidence", confidence)
            .put("raw_text", combined)
            .put("notification_hash", hash)
    }

    private fun findAmount(text: String): Double? {
        val matches = amountPattern.findAll(text).mapNotNull {
            it.groupValues.getOrNull(1)?.toDoubleOrNull()
        }.filter { it > 0 }.toList()
        return matches.maxOrNull()
    }

    private fun inferType(text: String): String? {
        val incomeWords = listOf("收款", "到账", "收入", "转入", "退款", "退回")
        val expenseWords = listOf("付款", "支付", "消费", "扣款", "支出", "转出")
        return when {
            incomeWords.any { text.contains(it) } -> "income"
            expenseWords.any { text.contains(it) } -> "expense"
            else -> null
        }
    }

    private fun inferMerchant(title: String, text: String, amount: Double): String {
        val normalizedAmount = amount.toString().trimEnd('0').trimEnd('.')
        val source = if (title.length >= 2 && !title.contains("支付")) title else text
        return source
            .replace(Regex("""(?:¥|￥)?\s*${Regex.escape(normalizedAmount)}0?\s*(?:元)?"""), "")
            .replace(Regex("""(微信支付|支付宝|银行|云闪付|付款|支付|消费|扣款|收款|到账|收入|支出|通知|提醒)"""), "")
            .replace(Regex("""\s+"""), " ")
            .trim()
            .take(min(24, source.length))
    }

    private fun sourceName(source: String): String {
        return when (source) {
            "wechat" -> "微信支付"
            "alipay" -> "支付宝"
            "unionpay" -> "云闪付"
            "bank" -> "银行提醒"
            else -> "支付通知"
        }
    }

    private fun confidenceFor(source: String, text: String): Double {
        var score = when (source) {
            "wechat", "alipay" -> 0.88
            "bank" -> 0.78
            else -> 0.72
        }
        if (text.contains("商户") || text.contains("收款方")) {
            score += 0.04
        }
        if (text.contains("余额") || text.contains("验证码")) {
            score -= 0.1
        }
        return score.coerceIn(0.45, 0.96)
    }

    private fun sha1(value: String): String {
        val digest = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(Locale.US, it) }
    }
}
