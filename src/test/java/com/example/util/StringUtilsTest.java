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
    @DisplayName("isEmpty: returns true for null")
    void testIsEmpty_Null() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: returns true for empty string")
    void testIsEmpty_EmptyString() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: returns true for ASCII whitespace-only string (spaces, tabs, newlines)")
    void testIsEmpty_AsciiWhitespaceOnly() {
        assertTrue(stringUtils.isEmpty(" \t\n "));
    }

    @Test
    @DisplayName("isEmpty: returns false for non-empty string")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("a"));
        assertFalse(stringUtils.isEmpty("  a  "));
    }

    @Test
    @DisplayName("isEmpty: returns false for Unicode whitespace (EM SPACE) because trim() doesn't remove it")
    void testIsEmpty_UnicodeEmSpaceOnly() {
        String emSpaceOnly = "\u2003"; // EM SPACE
        assertFalse(stringUtils.isEmpty(emSpaceOnly));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: returns null when input is null")
    void testReverse_Null() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: returns empty when input is empty")
    void testReverse_Empty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: single character remains the same")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: simple word")
    void testReverse_SimpleWord() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: preserves surrogate pairs (emoji)")
    void testReverse_EmojiSurrogatePairs() {
        String input = "A😀B";
        String expected = "B😀A";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: whitespace and punctuation")
    void testReverse_WhitespaceAndPunctuation() {
        assertEquals("! dlroW ,olleH", stringUtils.reverse("Hello, World! "));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: returns false for null")
    void testIsPalindrome_Null() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: returns true for empty string")
    void testIsPalindrome_Empty() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: returns true for whitespace-only string")
    void testIsPalindrome_WhitespaceOnly() {
        assertTrue(stringUtils.isPalindrome("   \t\n  "));
    }

    @Test
    @DisplayName("isPalindrome: true for 'racecar'")
    void testIsPalindrome_Racecar() {
        assertTrue(stringUtils.isPalindrome("racecar"));
    }

    @Test
    @DisplayName("isPalindrome: case-insensitive check")
    void testIsPalindrome_CaseInsensitive() {
        assertTrue(stringUtils.isPalindrome("Level"));
    }

    @Test
    @DisplayName("isPalindrome: ignores spaces")
    void testIsPalindrome_IgnoresSpaces() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome: with comma preserved, still palindrome")
    void testIsPalindrome_WithComma() {
        assertTrue(stringUtils.isPalindrome("No lemon, no melon"));
    }

    @Test
    @DisplayName("isPalindrome: returns false for non-palindromic string")
    void testIsPalindrome_NotPalindrome() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: returns 0 for null")
    void testCountWords_Null() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: returns 0 for empty string")
    void testCountWords_Empty() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: returns 0 for ASCII whitespace-only string")
    void testCountWords_AsciiWhitespaceOnly() {
        assertEquals(0, stringUtils.countWords("   \t  \n "));
    }

    @Test
    @DisplayName("countWords: returns 0 for Unicode whitespace-only (EM SPACE)")
    void testCountWords_UnicodeEmSpaceOnly() {
        assertEquals(0, stringUtils.countWords("\u2003"));
    }

    @Test
    @DisplayName("countWords: returns 1 for single word")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: counts multiple words separated by spaces")
    void testCountWords_MultipleWords() {
        assertEquals(3, stringUtils.countWords("one two three"));
    }

    @Test
    @DisplayName("countWords: counts with multiple spaces between words")
    void testCountWords_MultipleSpacesBetweenWords() {
        assertEquals(3, stringUtils.countWords("one   two    three"));
    }

    @Test
    @DisplayName("countWords: counts with newlines and tabs")
    void testCountWords_NewlinesAndTabs() {
        assertEquals(3, stringUtils.countWords("one\ntwo\tthree"));
    }

    @Test
    @DisplayName("countWords: ignores leading and trailing whitespace")
    void testCountWords_LeadingTrailingWhitespace() {
        assertEquals(2, stringUtils.countWords("   hello world   "));
    }

    @Test
    @DisplayName("countWords: punctuation without whitespace does not increase count")
    void testCountWords_PunctuationNoWhitespace() {
        assertEquals(1, stringUtils.countWords("hello,world"));
    }

    @Test
    @DisplayName("countWords: non-Latin characters")
    void testCountWords_NonLatin() {
        assertEquals(2, stringUtils.countWords("你好 世界"));
    }

    // Safety tests: ensure methods handle null without throwing
    @Test
    @DisplayName("No exceptions for null inputs across methods")
    void testNoExceptions_NullInputs() {
        assertDoesNotThrow(() -> stringUtils.isEmpty(null));
        assertDoesNotThrow(() -> stringUtils.reverse(null));
        assertDoesNotThrow(() -> stringUtils.isPalindrome(null));
        assertDoesNotThrow(() -> stringUtils.countWords(null));
    }
}