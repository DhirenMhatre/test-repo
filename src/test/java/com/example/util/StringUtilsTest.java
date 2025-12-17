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
    @DisplayName("isEmpty: Should return true for null")
    void testIsEmpty_Null() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: Should return true for empty string")
    void testIsEmpty_EmptyString() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: Should return true for whitespace-only string")
    void testIsEmpty_WhitespaceOnly() {
        assertTrue(stringUtils.isEmpty("   \t \n  "));
    }

    @Test
    @DisplayName("isEmpty: Should return false for non-empty string")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("a"));
    }

    @Test
    @DisplayName("isEmpty: Should return false for string with content and surrounding whitespace")
    void testIsEmpty_WhitespaceAroundContent() {
        assertFalse(stringUtils.isEmpty("   content   "));
    }

    @Test
    @DisplayName("isEmpty: Should treat non-breaking space as not empty (trim does not remove NBSP)")
    void testIsEmpty_NonBreakingSpace() {
        String nbspOnly = "\u00A0";
        assertFalse(stringUtils.isEmpty(nbspOnly));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: Should return null for null input")
    void testReverse_Null() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: Should return empty string for empty input")
    void testReverse_Empty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: Should handle single character")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: Should reverse a simple string")
    void testReverse_SimpleString() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: Should reverse string with spaces")
    void testReverse_WithSpaces() {
        assertEquals("dc ba", stringUtils.reverse("ab cd"));
    }

    @Test
    @DisplayName("reverse: Should reverse string with emoji (surrogate pairs)")
    void testReverse_Emoji() {
        String input = "😀👍";
        String expected = "👍😀";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: Should not throw and handle long strings")
    void testReverse_LongString_DoesNotThrow() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 10000; i++) {
            sb.append('a');
        }
        String longString = sb.toString();
        assertDoesNotThrow(() -> {
            String result = stringUtils.reverse(longString);
            assertEquals(longString, result); // reversing all 'a's yields the same string
        });
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: Should return false for null")
    void testIsPalindrome_Null() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: Should return true for empty string")
    void testIsPalindrome_EmptyString() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: Should return true for whitespace-only string (ignores spaces)")
    void testIsPalindrome_WhitespaceOnly() {
        assertTrue(stringUtils.isPalindrome("   \t \n  "));
    }

    @Test
    @DisplayName("isPalindrome: Should detect simple palindrome")
    void testIsPalindrome_SimpleTrue() {
        assertTrue(stringUtils.isPalindrome("madam"));
    }

    @Test
    @DisplayName("isPalindrome: Should be case-insensitive")
    void testIsPalindrome_CaseInsensitive() {
        assertTrue(stringUtils.isPalindrome("Madam"));
    }

    @Test
    @DisplayName("isPalindrome: Should ignore spaces in phrases")
    void testIsPalindrome_PhraseWithSpaces() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome: Should return false for non-palindrome")
    void testIsPalindrome_FalseCase() {
        assertFalse(stringUtils.isPalindrome("not a palindrome"));
    }

    @Test
    @DisplayName("isPalindrome: Should not ignore punctuation (comma breaks palindrome)")
    void testIsPalindrome_PunctuationConsidered() {
        assertFalse(stringUtils.isPalindrome("Able was I, ere I saw Elba"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: Should return 0 for null")
    void testCountWords_Null() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: Should return 0 for empty string")
    void testCountWords_EmptyString() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: Should return 0 for whitespace-only string")
    void testCountWords_WhitespaceOnly() {
        assertEquals(0, stringUtils.countWords("   \n\t  "));
    }

    @Test
    @DisplayName("countWords: Should count single word")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: Should count words separated by multiple spaces/tabs/newlines")
    void testCountWords_MixedWhitespace() {
        assertEquals(4, stringUtils.countWords("hello   world\tfoo\nbar"));
    }

    @Test
    @DisplayName("countWords: Should handle leading and trailing whitespace")
    void testCountWords_LeadingTrailingWhitespace() {
        assertEquals(2, stringUtils.countWords("   hello world   "));
    }

    @Test
    @DisplayName("countWords: Should count words with punctuation as part of tokens")
    void testCountWords_Punctuation() {
        assertEquals(2, stringUtils.countWords("hello, world!"));
    }

    @Test
    @DisplayName("countWords: Non-breaking space is not treated as delimiter by trim/split")
    void testCountWords_NonBreakingSpace() {
        String nbsp = "\u00A0";
        assertEquals(1, stringUtils.countWords("hello" + nbsp + "world"));
    }
}