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
    void testIsEmpty_NullString_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: empty string -> true")
    void testIsEmpty_EmptyString_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: whitespace-only -> true")
    void testIsEmpty_WhitespaceOnly_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty("   \t\n  "));
    }

    @Test
    @DisplayName("isEmpty: non-empty -> false")
    void testIsEmpty_NonEmpty_ReturnsFalse() {
        assertFalse(stringUtils.isEmpty("a"));
    }

    @Test
    @DisplayName("isEmpty: text with surrounding spaces -> false")
    void testIsEmpty_TextWithSpaces_ReturnsFalse() {
        assertFalse(stringUtils.isEmpty("  hello  "));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null -> null")
    void testReverse_Null_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty -> empty")
    void testReverse_Empty_ReturnsEmpty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: single character remains unchanged")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: palindrome remains same when reversed")
    void testReverse_PalindromeStaysSame() {
        assertEquals("aba", stringUtils.reverse("aba"));
    }

    @Test
    @DisplayName("reverse: normal string reversed correctly")
    void testReverse_NormalString() {
        assertEquals("olleH", stringUtils.reverse("Hello"));
    }

    @Test
    @DisplayName("reverse: preserves whitespace positions in reverse")
    void testReverse_WithWhitespace() {
        assertEquals(" ba ", stringUtils.reverse(" ab "));
    }

    @Test
    @DisplayName("reverse: handles Unicode emoji correctly")
    void testReverse_UnicodeEmoji() {
        String input = "A😀B";
        String expected = "B😀A";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: does not throw for large input")
    void testReverse_DoesNotThrowForLargeInput() {
        String large = "a".repeat(10_000);
        assertDoesNotThrow(() -> stringUtils.reverse(large));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null -> false")
    void testIsPalindrome_Null_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: empty -> true")
    void testIsPalindrome_Empty_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: whitespace-only -> true (whitespace ignored)")
    void testIsPalindrome_WhitespaceOnly_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("   \t  "));
    }

    @Test
    @DisplayName("isPalindrome: case-insensitive match")
    void testIsPalindrome_SimpleTrue_CaseInsensitive() {
        assertTrue(stringUtils.isPalindrome("RaceCar"));
    }

    @Test
    @DisplayName("isPalindrome: phrase with spaces -> true")
    void testIsPalindrome_PhraseWithSpaces_True() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome -> false")
    void testIsPalindrome_NonPalindrome_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation not ignored -> false")
    void testIsPalindrome_WithPunctuation_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome("Madam, I'm Adam"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: null -> 0")
    void testCountWords_Null_ReturnsZero() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: empty -> 0")
    void testCountWords_Empty_ReturnsZero() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: whitespace-only -> 0")
    void testCountWords_WhitespaceOnly_ReturnsZero() {
        assertEquals(0, stringUtils.countWords("   \n\t  "));
    }

    @Test
    @DisplayName("countWords: single word -> 1")
    void testCountWords_SingleWord_ReturnsOne() {
        assertEquals(1, stringUtils.countWords("one"));
    }

    @Test
    @DisplayName("countWords: two words -> 2")
    void testCountWords_TwoWords_ReturnsTwo() {
        assertEquals(2, stringUtils.countWords("two words"));
    }

    @Test
    @DisplayName("countWords: multiple spaces between words counted correctly")
    void testCountWords_MultipleSpacesBetweenWords() {
        assertEquals(3, stringUtils.countWords("multiple   spaces   between"));
    }

    @Test
    @DisplayName("countWords: leading and trailing whitespace handled correctly")
    void testCountWords_LeadingTrailingWhitespace() {
        assertEquals(4, stringUtils.countWords("  leading and trailing  spaces "));
    }

    @Test
    @DisplayName("countWords: newlines and tabs treated as separators")
    void testCountWords_LinesAndTabs() {
        assertEquals(3, stringUtils.countWords("line1\nline2\tline3"));
    }

    @Test
    @DisplayName("countWords: punctuation stays with words when splitting on whitespace")
    void testCountWords_PunctuationTreatedAsPartOfWords() {
        assertEquals(2, stringUtils.countWords("hi, there!"));
    }
}