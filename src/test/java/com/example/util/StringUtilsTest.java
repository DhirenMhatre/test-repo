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
    @DisplayName("isEmpty: null -> true")
    void testIsEmpty_Null() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: empty string -> true")
    void testIsEmpty_EmptyString() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: whitespace-only -> true")
    void testIsEmpty_WhitespaceOnly() {
        assertTrue(stringUtils.isEmpty("   \t\n  "));
    }

    @Test
    @DisplayName("isEmpty: non-empty -> false")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("a"));
    }

    @Test
    @DisplayName("isEmpty: whitespace around text -> false")
    void testIsEmpty_WhitespaceAroundText() {
        assertFalse(stringUtils.isEmpty("  hello  "));
    }

    @Test
    @DisplayName("isEmpty: non-breaking space only (\\u00A0) -> false due to trim() behavior")
    void testIsEmpty_NonBreakingSpaceOnly() {
        String nbsp = "\u00A0";
        assertFalse(stringUtils.isEmpty(nbsp));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null -> null")
    void testReverse_Null() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty string -> empty string")
    void testReverse_Empty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: simple string")
    void testReverse_Simple() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: single character")
    void testReverse_SingleCharacter() {
        assertEquals("x", stringUtils.reverse("x"));
    }

    @Test
    @DisplayName("reverse: with spaces preserved")
    void testReverse_WithSpaces() {
        assertEquals(" b a ", stringUtils.reverse(" a b "));
    }

    @Test
    @DisplayName("reverse: non-ASCII characters")
    void testReverse_NonAscii() {
        assertEquals("çbá", stringUtils.reverse("ábç"));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null -> false")
    void testIsPalindrome_Null() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: empty string -> true")
    void testIsPalindrome_EmptyString() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: whitespace-only -> true (ignores spaces)")
    void testIsPalindrome_WhitespaceOnly() {
        assertTrue(stringUtils.isPalindrome("   \t  "));
    }

    @Test
    @DisplayName("isPalindrome: single character -> true")
    void testIsPalindrome_SingleCharacter() {
        assertTrue(stringUtils.isPalindrome("x"));
    }

    @Test
    @DisplayName("isPalindrome: simple palindrome -> true")
    void testIsPalindrome_SimpleTrue() {
        assertTrue(stringUtils.isPalindrome("racecar"));
    }

    @Test
    @DisplayName("isPalindrome: ignores spaces and case")
    void testIsPalindrome_IgnoresSpacesAndCase() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation not ignored -> false")
    void testIsPalindrome_PunctuationNotIgnored() {
        assertFalse(stringUtils.isPalindrome("Able was I, ere I saw Elba"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome -> false")
    void testIsPalindrome_FalseCase() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: null -> 0")
    void testCountWords_Null() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: empty string -> 0")
    void testCountWords_Empty() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: whitespace-only -> 0")
    void testCountWords_WhitespaceOnly() {
        assertEquals(0, stringUtils.countWords("   \n\t  "));
    }

    @Test
    @DisplayName("countWords: simple two words")
    void testCountWords_SimpleTwoWords() {
        assertEquals(2, stringUtils.countWords("hello world"));
    }

    @Test
    @DisplayName("countWords: multiple spaces, tabs, newlines")
    void testCountWords_MixedWhitespace() {
        assertEquals(4, stringUtils.countWords("one   two\tthree\nfour"));
    }

    @Test
    @DisplayName("countWords: leading and trailing whitespace")
    void testCountWords_LeadingTrailingWhitespace() {
        assertEquals(3, stringUtils.countWords("  one two three  "));
    }

    @Test
    @DisplayName("countWords: punctuation attached to word (no whitespace) counts as one")
    void testCountWords_PunctuationAttached() {
        assertEquals(1, stringUtils.countWords("hello,world"));
    }

    @Test
    @DisplayName("countWords: punctuation separated by whitespace counts as separate words")
    void testCountWords_PunctuationSeparated() {
        assertEquals(2, stringUtils.countWords("hello, world!"));
    }

    @Test
    @DisplayName("countWords: non-breaking space (\\u00A0) is not treated as whitespace by split")
    void testCountWords_NonBreakingSpace() {
        String input = " \u00A0 ";
        assertEquals(1, stringUtils.countWords(input));
    }
}