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
    @DisplayName("isEmpty: should return true for null")
    void testIsEmpty_Null() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: should return true for empty string")
    void testIsEmpty_EmptyString() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: should return true for whitespace-only string")
    void testIsEmpty_WhitespaceOnly() {
        assertTrue(stringUtils.isEmpty("   "));
    }

    @Test
    @DisplayName("isEmpty: should return true for tabs and newlines")
    void testIsEmpty_TabsAndNewlines() {
        assertTrue(stringUtils.isEmpty("\n\t  \t\n"));
    }

    @Test
    @DisplayName("isEmpty: should return false for non-empty string")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("a"));
    }

    @Test
    @DisplayName("isEmpty: should return false for string with spaces around text")
    void testIsEmpty_SpacesAroundText() {
        assertFalse(stringUtils.isEmpty("  hello  "));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: should return null for null input")
    void testReverse_Null() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: should return empty string for empty input")
    void testReverse_Empty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: should return same string for single character")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: should reverse a simple word")
    void testReverse_SimpleWord() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: should keep palindrome unchanged after reverse")
    void testReverse_Palindrome() {
        assertEquals("madam", stringUtils.reverse("madam"));
    }

    @Test
    @DisplayName("reverse: should reverse string with spaces")
    void testReverse_WithSpaces() {
        assertEquals("b a", stringUtils.reverse("a b"));
        assertEquals(" ba ", stringUtils.reverse(" ab "));
    }

    @Test
    @DisplayName("reverse: should correctly reverse Unicode emoji")
    void testReverse_UnicodeEmoji() {
        String input = "A😀👍B";
        String expected = "B👍😀A";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: should reverse multi-byte Latin characters")
    void testReverse_MultiByteLatin() {
        assertEquals("çßå", stringUtils.reverse("åßç"));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: should return false for null")
    void testIsPalindrome_Null() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: should return true for empty string")
    void testIsPalindrome_Empty() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: should return true for whitespace-only string")
    void testIsPalindrome_WhitespaceOnly() {
        assertTrue(stringUtils.isPalindrome("   "));
    }

    @Test
    @DisplayName("isPalindrome: should return true for single character")
    void testIsPalindrome_SingleCharacter() {
        assertTrue(stringUtils.isPalindrome("a"));
    }

    @Test
    @DisplayName("isPalindrome: should return true for simple palindrome")
    void testIsPalindrome_SimplePalindrome() {
        assertTrue(stringUtils.isPalindrome("level"));
    }

    @Test
    @DisplayName("isPalindrome: should ignore case and spaces")
    void testIsPalindrome_IgnoresCaseAndSpaces() {
        assertTrue(stringUtils.isPalindrome("Race car"));
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
        assertTrue(stringUtils.isPalindrome("No lemon no melon"));
    }

    @Test
    @DisplayName("isPalindrome: should return false for non-palindrome")
    void testIsPalindrome_NotPalindrome() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation is not ignored (should return false)")
    void testIsPalindrome_PunctuationNotIgnored() {
        assertFalse(stringUtils.isPalindrome("Madam, I'm Adam"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: should return 0 for null")
    void testCountWords_Null() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: should return 0 for empty string")
    void testCountWords_Empty() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: should return 0 for whitespace-only string")
    void testCountWords_WhitespaceOnly() {
        assertEquals(0, stringUtils.countWords("   \t \n "));
    }

    @Test
    @DisplayName("countWords: should return 1 for single word")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: should count multiple words with single spaces")
    void testCountWords_MultipleWords_SingleSpaces() {
        assertEquals(3, stringUtils.countWords("one two three"));
    }

    @Test
    @DisplayName("countWords: should count words with mixed whitespace")
    void testCountWords_MixedWhitespace() {
        assertEquals(4, stringUtils.countWords("one   two\tthree\nfour"));
    }

    @Test
    @DisplayName("countWords: should ignore leading and trailing spaces")
    void testCountWords_LeadingTrailingSpaces() {
        assertEquals(2, stringUtils.countWords("  hello world  "));
    }

    @Test
    @DisplayName("countWords: punctuation remains part of tokens")
    void testCountWords_PunctuationTokens() {
        assertEquals(2, stringUtils.countWords("hello, world!"));
    }
}