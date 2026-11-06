package app.arabwriter.android.service

import org.junit.Assert.assertEquals
import org.junit.Test

class DetectTest {
    private fun d(t: String) = TranslateDirection.AUTO.resolved(t)

    @Test fun arabic() = assertEquals(TranslateDirection.TO_ENGLISH, d("جربت التطبيق امس والنتيجه ممتازه"))
    @Test fun english() = assertEquals(TranslateDirection.TO_ARABIC, d("I tried the app yesterday, it was great"))
    @Test fun arabicWithEnglishNames() = assertEquals(TranslateDirection.TO_ENGLISH, d("استخدمت Claude و ChatGPT في شغلي اليومي وكانت التجربة مفيدة"))
    @Test fun presentationForms() = assertEquals(TranslateDirection.TO_ENGLISH, d("ﺍﻟﺴﻼﻡ ﻋﻠﻴﻜﻢ ﻭﺭﺣﻤﺔ ﺍﻟﻠﻪ"))
    @Test fun englishWithLink() = assertEquals(TranslateDirection.TO_ARABIC, d("Check https://example.com/مقال for details"))
}
