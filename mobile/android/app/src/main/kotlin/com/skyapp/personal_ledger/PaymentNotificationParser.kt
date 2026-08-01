package com.skyapp.personal_ledger

import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.min

object PaymentNotificationParser {
    private val amountPattern = Regex(
        """(?:¥|￥)?\s*(?<![\d,.])((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?)(?![\d,.])\s*(?:元)?""",
    )

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
        return parseFields(
            packageName = packageName,
            title = title,
            text = text,
            postedAtMillis = postedAtMillis,
        )?.toJson()
    }

    fun parseFields(
        packageName: String,
        title: String,
        text: String,
        postedAtMillis: Long,
    ): ParsedPaymentNotification? {
        val source = sourceId(packageName) ?: return null
        val combined = listOf(title, text).joinToString(" ").trim()
        if (combined.isBlank()) {
            return null
        }

        val type = inferType(combined) ?: return null
        val amount = findAmount(combined, type) ?: return null
        val merchant = inferMerchant(title, text, amount.matchedText).ifBlank { sourceName(source) }
        val hash = sha1("$packageName|$postedAtMillis|$combined")
        val confidence = confidenceFor(source, combined)

        return ParsedPaymentNotification(
            id = "android-$hash",
            source = "android_notification",
            sourceName = sourceName(source),
            sourceId = source,
            type = type,
            amount = amount.value,
            merchant = merchant,
            occurredAt = postedAtMillis,
            confidence = confidence,
            rawText = combined,
            notificationHash = hash,
        )
    }

    private fun findAmount(text: String, type: String): AmountCandidate? {
        val directionalWords = if (type == "income") {
            listOf("收款", "到账", "收入", "转入", "退款", "退回", "收到")
        } else {
            listOf("付款", "支付", "消费", "扣款", "支出", "转出")
        }
        var best: AmountCandidate? = null
        for (match in amountPattern.findAll(text)) {
            val amountToken = match.groupValues.getOrNull(1).orEmpty()
            val value = amountToken.replace(",", "").toDoubleOrNull() ?: continue
            if (value <= 0 || looksLikeDateOrTime(text, match.range)) {
                continue
            }
            val before = text
                .substring(maxOf(0, match.range.first - 14), match.range.first)
            val after = text
                .substring(match.range.last + 1, min(text.length, match.range.last + 15))
            val afterWithoutUnit = after.trimStart()
                .removePrefix("元")
                .trimStart()
            val isBalance = Regex("""(?:余额|可用|剩余)\s*[:：]?\s*[¥￥]?\s*$""")
                .containsMatchIn(before) ||
                listOf("余额", "可用", "剩余").any { afterWithoutUnit.startsWith(it) }
            if (isBalance) {
                continue
            }
            val hasDirectionalCue = directionalWords.any {
                before.contains(it) || after.contains(it)
            }
            val matchedText = match.value
            val hasCurrencyUnit = matchedText.contains('¥') ||
                matchedText.contains('￥') ||
                matchedText.trimEnd().endsWith("元")
            val hasAmountLabel = listOf("金额", "实付", "合计").any {
                before.contains(it) || after.startsWith(it)
            }
            val hasUnlabeledDecimalAmount = hasDirectionalCue && amountToken.contains('.')
            if (!hasCurrencyUnit && !hasAmountLabel && !hasUnlabeledDecimalAmount) {
                continue
            }
            val candidate = AmountCandidate(
                value = value,
                score = (if (hasDirectionalCue) 4 else 0) +
                    (if (hasCurrencyUnit) 4 else 0) +
                    (if (hasAmountLabel) 3 else 0),
                index = match.range.first,
                matchedText = matchedText,
            )
            if (best == null ||
                candidate.score > best.score ||
                (candidate.score == best.score && candidate.index < best.index)
            ) {
                best = candidate
            }
        }
        return best
    }

    private fun looksLikeDateOrTime(text: String, range: IntRange): Boolean {
        val previous = text.getOrNull(range.first - 1)
        val next = text.getOrNull(range.last + 1)
        return previous == '-' || previous == '/' || previous == ':' ||
            next == '-' || next == '/' || next == ':'
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

    private fun inferMerchant(title: String, text: String, matchedAmount: String): String {
        val source = if (title.length >= 2 && !title.contains("支付")) title else text
        return source
            .replace(Regex(Regex.escape(matchedAmount)), "")
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

    private data class AmountCandidate(
        val value: Double,
        val score: Int,
        val index: Int,
        val matchedText: String,
    )

    data class ParsedPaymentNotification(
        val id: String,
        val source: String,
        val sourceName: String,
        val sourceId: String,
        val type: String,
        val amount: Double,
        val merchant: String,
        val occurredAt: Long,
        val confidence: Double,
        val rawText: String,
        val notificationHash: String,
    ) {
        fun toJson(): JSONObject {
            return JSONObject()
                .put("id", id)
                .put("source", source)
                .put("source_name", sourceName)
                .put("source_id", sourceId)
                .put("type", type)
                .put("amount", amount)
                .put("merchant", merchant)
                .put("occurred_at", occurredAt)
                .put("confidence", confidence)
                .put("raw_text", rawText)
                .put("notification_hash", notificationHash)
        }
    }
}
