package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("StringUtils Tests")
class StringUtilsTest {

    private StringUtils stringUtils;

    @BeforeEach
    void setUp() {
        stringUtils = new StringUtils();
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
    }

    @Test
    @DisplayName("Should create instance successfully")
    void testConstructor() {
        assertNotNull(stringUtils);
    }

    // isEmpty tests

    @Test
    @DisplayName("isEmpty: null input should be empty")
    void testIsEmpty_NullInput() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: empty string should be empty")
    void testIsEmpty_EmptyString() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: whitespace-only string should be empty")
    void testIsEmpty_WhitespaceOnly() {
        assertTrue(stringUtils.isEmpty("   "));
        assertTrue(stringUtils.isEmpty("\t\n\r"));
    }

    @Test
    @DisplayName("isEmpty: non-empty string should not be empty")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("a"));
    }

    @Test
    @DisplayName("isEmpty: string with surrounding whitespace and characters should not be empty")
    void testIsEmpty_SurroundingWhitespaceAndChars() {
        assertFalse(stringUtils.isEmpty("  a  "));
        assertFalse(stringUtils.isEmpty("\t a \n"));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_NullInput() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty string should return empty string")
    void testReverse_EmptyString() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: single character should remain unchanged")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: normal string should be reversed")
    void testReverse_NormalString() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: string with spaces should be reversed including spaces")
    void testReverse_StringWithSpaces() {
        assertEquals("b a", stringUtils.reverse("a b"));
    }

    @Test
    @DisplayName("reverse: unicode emojis should be reversed correctly")
    void testReverse_UnicodeEmojis() {
        // Two emojis reversed should swap positions and remain intact
        String input = "🙂👍";
        String expected = "👍🙂";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: combining characters should reverse code units")
    void testReverse_CombiningCharacters() {
        // 'e' + combining acute accent
        String input = "e\u0301";
        String expected = "\u0301e";
        assertEquals(expected, stringUtils.reverse(input));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null input should return false")
    void testIsPalindrome_NullInput() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: empty string should be palindrome")
    void testIsPalindrome_EmptyString() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: whitespace-only string should be palindrome")
    void testIsPalindrome_WhitespaceOnly() {
        assertTrue(stringUtils.isPalindrome("   "));
        assertTrue(stringUtils.isPalindrome("\t \n"));
    }

    @Test
    @DisplayName("isPalindrome: simple palindrome should return true")
    void testIsPalindrome_SimplePalindrome() {
        assertTrue(stringUtils.isPalindrome("racecar"));
        assertTrue(stringUtils.isPalindrome("level"));
        assertTrue(stringUtils.isPalindrome("noon"));
    }

    @Test
    @DisplayName("isPalindrome: mixed case and spaces should be ignored")
    void testIsPalindrome_MixedCaseAndSpaces() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
        assertTrue(stringUtils.isPalindrome("Never Odd Or Even"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome should return false")
    void testIsPalindrome_NonPalindrome() {
        assertFalse(stringUtils.isPalindrome("hello"));
        assertFalse(stringUtils.isPalindrome("openai"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation is not ignored, so should return false when punctuation disrupts palindrome")
    void testIsPalindrome_WithPunctuation_ReturnsFalse() {
        // Spaces are removed, but commas/apostrophes remain, breaking palindrome
        assertFalse(stringUtils.isPalindrome("Madam, I'm Adam"));
    }

    @Test
    @DisplayName("isPalindrome: leading and trailing spaces should be ignored")
    void testIsPalindrome_LeadingTrailingSpaces() {
        assertTrue(stringUtils.isPalindrome("  mom  "));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: null input should return 0")
    void testCountWords_NullInput() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: empty string should return 0")
    void testCountWords_EmptyString() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: whitespace-only string should return 0")
    void testCountWords_WhitespaceOnly() {
        assertEquals(0, stringUtils.countWords("   "));
        assertEquals(0, stringUtils.countWords("\t \n"));
    }

    @Test
    @DisplayName("countWords: single word should return 1")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: multiple words separated by single spaces")
    void testCountWords_MultipleWords_SingleSpaces() {
        assertEquals(3, stringUtils.countWords("one two three"));
    }

    @Test
    @DisplayName("countWords: multiple whitespace types should be handled")
    void testCountWords_MultipleWhitespaceTypes() {
        assertEquals(4, stringUtils.countWords("one\ttwo\nthree  four"));
    }

    @Test
    @DisplayName("countWords: leading and trailing spaces should be ignored")
    void testCountWords_LeadingTrailingSpaces() {
        assertEquals(2, stringUtils.countWords("  hello world  "));
    }

    @Test
    @DisplayName("countWords: contractions and punctuation within words should not split words")
    void testCountWords_WithContractionsAndPunctuation() {
        assertEquals(4, stringUtils.countWords("can't stop won't stop"));
        assertEquals(3, stringUtils.countWords("word1, word2; word3."));
    }

    @Test
    @DisplayName("countWords: non-ASCII characters and emojis should be counted as words when separated by spaces")
    void testCountWords_NonAsciiAndEmoji() {
        assertEquals(2, stringUtils.countWords("你好 世界"));
        assertEquals(2, stringUtils.countWords("🙂 👍"));
    }

    @Test
    @DisplayName("countWords: long input should count many words correctly")
    void testCountWords_LongInput() {
        StringBuilder sb = new StringBuilder();
        int words = 1000;
        for (int i = 0; i < words; i++) {
            if (i > 0) sb.append(' ');
            sb.append("word");
        }
        assertEquals(words, stringUtils.countWords(sb.toString()));
    }
}