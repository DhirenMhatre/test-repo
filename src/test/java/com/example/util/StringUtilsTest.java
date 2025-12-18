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
    @DisplayName("isEmpty: whitespace-only (spaces) -> true")
    void testIsEmpty_WhitespaceSpacesOnly() {
        assertTrue(stringUtils.isEmpty("   "));
    }

    @Test
    @DisplayName("isEmpty: whitespace-only (tabs/newlines) -> true")
    void testIsEmpty_TabsNewlinesOnly() {
        assertTrue(stringUtils.isEmpty("\t \n  \r"));
    }

    @Test
    @DisplayName("isEmpty: non-empty string -> false")
    void testIsEmpty_NonEmpty() {
        assertFalse(stringUtils.isEmpty("abc"));
    }

    @Test
    @DisplayName("isEmpty: non-empty after trim -> false")
    void testIsEmpty_NonEmptyAfterTrim() {
        assertFalse(stringUtils.isEmpty("  abc  "));
    }

    @Test
    @DisplayName("isEmpty: non-breaking space only (\\u00A0) -> false (not trimmed by String.trim)")
    void testIsEmpty_NonBreakingSpaceOnly() {
        assertFalse(stringUtils.isEmpty("\u00A0"));
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
    @DisplayName("reverse: single character -> same character")
    void testReverse_SingleChar() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: simple string")
    void testReverse_Simple() {
        assertEquals("cba", stringUtils.reverse("abc"));
    }

    @Test
    @DisplayName("reverse: palindrome remains the same")
    void testReverse_Palindrome() {
        assertEquals("madam", stringUtils.reverse("madam"));
    }

    @Test
    @DisplayName("reverse: preserves spaces in reversed order")
    void testReverse_WithSpaces() {
        assertEquals(" b a ", stringUtils.reverse(" a b "));
    }

    @Test
    @DisplayName("reverse: handles surrogate pairs (emoji) correctly")
    void testReverse_UnicodeEmoji() {
        String input = "A\uD83D\uDE42B";   // A🙂B
        String expected = "B\uD83D\uDE42A"; // B🙂A
        assertEquals(expected, stringUtils.reverse(input));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null -> false")
    void testIsPalindrome_Null() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: empty string -> true")
    void testIsPalindrome_Empty() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: spaces only -> true (ignored in check)")
    void testIsPalindrome_SpacesOnly() {
        assertTrue(stringUtils.isPalindrome("     "));
    }

    @Test
    @DisplayName("isPalindrome: simple palindrome lowercase -> true")
    void testIsPalindrome_SimpleTrue() {
        assertTrue(stringUtils.isPalindrome("racecar"));
    }

    @Test
    @DisplayName("isPalindrome: case-insensitive palindrome -> true")
    void testIsPalindrome_CaseInsensitive() {
        assertTrue(stringUtils.isPalindrome("RaceCar"));
    }

    @Test
    @DisplayName("isPalindrome: palindrome with spaces -> true")
    void testIsPalindrome_WithSpaces() {
        assertTrue(stringUtils.isPalindrome("nurses run"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation not ignored -> false")
    void testIsPalindrome_WithPunctuationFalse() {
        assertFalse(stringUtils.isPalindrome("A man, a plan, a canal: Panama"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome -> false")
    void testIsPalindrome_SimpleFalse() {
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
        assertEquals(0, stringUtils.countWords("   \t  \n "));
    }

    @Test
    @DisplayName("countWords: single word -> 1")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: multiple words with multiple spaces -> 3")
    void testCountWords_MultipleSpaces() {
        assertEquals(3, stringUtils.countWords("  one   two   three "));
    }

    @Test
    @DisplayName("countWords: words separated by tabs and newlines -> 3")
    void testCountWords_MixedWhitespace() {
        assertEquals(3, stringUtils.countWords("one\ttwo\nthree"));
    }

    @Test
    @DisplayName("countWords: punctuation without spaces counts as single token -> 1")
    void testCountWords_PunctuationNoSpace() {
        assertEquals(1, stringUtils.countWords("hello,world"));
    }

    @Test
    @DisplayName("countWords: non-breaking space only (\\u00A0) -> 1 (not treated as trim/whitespace)")
    void testCountWords_NonBreakingSpaceOnly() {
        assertEquals(1, stringUtils.countWords("\u00A0"));
    }

    @Test
    @DisplayName("countWords: non-Latin words separated by space -> 2")
    void testCountWords_NonLatin() {
        assertEquals(2, stringUtils.countWords("两个 汉字"));
    }

    @Test
    @DisplayName("countWords: leading and trailing whitespace -> count correct")
    void testCountWords_LeadingTrailingWhitespace() {
        assertEquals(2, stringUtils.countWords("  hello world  "));
    }
}