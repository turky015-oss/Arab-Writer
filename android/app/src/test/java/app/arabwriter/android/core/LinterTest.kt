package app.arabwriter.android.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LinterTest {
    @Test fun markersAreBlocking() {
        val r = ArabicLinter.check("في عالم اليوم أصبحت التقنية مهمة.")
        assertTrue(r.errors.any { it.kind.startsWith("بصمة آلية") })
    }

    @Test fun spellingFix() {
        val out = ArabicLinter.fix("ذهبت الى المدرسه وهذة فكره جيدة امس.", englishOnOwnLine = false)
        assertTrue(out, out.contains("إلى"))
        assertTrue(out, out.contains("هذه"))
        assertTrue(out, out.contains("فكرة"))
        assertTrue(out, out.contains("أمس"))
    }

    @Test fun punctuationFix() {
        assertEquals("كيف حالك؟", ArabicLinter.fix("كيف حالك?", englishOnOwnLine = false))
    }

    @Test fun englishOnOwnLine() {
        val out = ArabicLinter.fix("استخدمت Claude في العمل")
        assertEquals("استخدمت\nClaude\nفي العمل", out)
        assertTrue(ArabicLinter.check(out).isClean)
    }

    @Test fun fabrication() {
        val r = ArabicLinter.check("زاد الدخل 40%", LintOptions(source = "زاد الدخل"))
        assertTrue(r.errors.any { it.kind == "اختلاق" })
    }

    @Test fun cleanText() {
        val r = ArabicLinter.check("حمّلت التطبيق أمس وجربته على جهازي.")
        assertTrue(r.errors.toString(), r.isClean)
    }

    @Test fun emojiRemoved() {
        assertEquals("ممتاز", ArabicLinter.fix("ممتاز 🚀", englishOnOwnLine = false))
    }

    @Test fun inlineFixCounts() {
        val (out, n) = ArabicLinter.fixInline("ذهبت الى البيت")
        assertEquals("ذهبت إلى البيت", out)
        assertTrue(n >= 1)
    }

    @Test fun diff() {
        val (changes, _) = TextDiff.compare("ذهبت الى البيت", "ذهبت إلى البيت")
        assertEquals(1, changes.size)
        assertEquals(DiffChange.Op.REPLACE, changes.first().op)
    }
}
