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
    @DisplayName("isEmpty: null string returns true")
    void testIsEmpty_Null_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @Test
    @DisplayName("isEmpty: empty string returns true")
    void testIsEmpty_EmptyString_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty(""));
    }

    @Test
    @DisplayName("isEmpty: whitespace-only string returns true")
    void testIsEmpty_WhitespaceOnly_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty("   "));
    }

    @Test
    @DisplayName("isEmpty: tabs and newlines only return true")
    void testIsEmpty_TabsAndNewlinesOnly_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty("\t\n\r\f  \n"));
    }

    @Test
    @DisplayName("isEmpty: non-empty string returns false")
    void testIsEmpty_NonEmpty_ReturnsFalse() {
        assertFalse(stringUtils.isEmpty(" a "));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null returns null")
    void testReverse_Null_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty string returns empty string")
    void testReverse_EmptyString_ReturnsEmpty() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: single character remains unchanged")
    void testReverse_SingleCharacter() {
        assertEquals("a", stringUtils.reverse("a"));
    }

    @Test
    @DisplayName("reverse: two characters are swapped")
    void testReverse_TwoCharacters() {
        assertEquals("ba", stringUtils.reverse("ab"));
    }

    @Test
    @DisplayName("reverse: handles surrogate pair emoji correctly")
    void testReverse_UnicodeEmoji() {
        String input = "Hi😊";
        String expected = "😊iH";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: handles spaces and punctuation")
    void testReverse_WithSpacesAndPunctuation() {
        assertEquals("!dlroW ,olleH", stringUtils.reverse("Hello, World!"));
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null returns false")
    void testIsPalindrome_Null_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: empty string returns true")
    void testIsPalindrome_EmptyString_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome(""));
    }

    @Test
    @DisplayName("isPalindrome: whitespace-only string returns true")
    void testIsPalindrome_WhitespaceOnly_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("   "));
    }

    @Test
    @DisplayName("isPalindrome: simple palindrome returns true")
    void testIsPalindrome_SimplePalindrome() {
        assertTrue(stringUtils.isPalindrome("racecar"));
    }

    @Test
    @DisplayName("isPalindrome: ignores case and spaces")
    void testIsPalindrome_IgnoresCaseAndSpaces() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome returns false")
    void testIsPalindrome_NotPalindrome() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: null returns 0")
    void testCountWords_Null_ReturnsZero() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @Test
    @DisplayName("countWords: empty string returns 0")
    void testCountWords_EmptyString_ReturnsZero() {
        assertEquals(0, stringUtils.countWords(""));
    }

    @Test
    @DisplayName("countWords: whitespace-only returns 0")
    void testCountWords_WhitespaceOnly_ReturnsZero() {
        assertEquals(0, stringUtils.countWords("   \t \n "));
    }

    @Test
    @DisplayName("countWords: single word returns 1")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("hello"));
    }

    @Test
    @DisplayName("countWords: multiple words with single spaces")
    void testCountWords_MultipleWords_SingleSpaces() {
        assertEquals(3, stringUtils.countWords("one two three"));
    }

    @Test
    @DisplayName("countWords: multiple words with multiple spaces")
    void testCountWords_MultipleWords_MultipleSpaces() {
        assertEquals(3, stringUtils.countWords("  multiple   spaces  here "));
    }

    @Test
    @DisplayName("countWords: mixed whitespace (spaces, tabs, newlines)")
    void testCountWords_MixedWhitespace() {
        assertEquals(3, stringUtils.countWords("one\ttwo\nthree"));
    }

    @Test
    @DisplayName("countWords: words with punctuation are counted correctly")
    void testCountWords_PunctuationAttached() {
        assertEquals(2, stringUtils.countWords("Hello, world!"));
    }

    // Null-safety does not throw

    @Test
    @DisplayName("Null inputs do not throw exceptions for any method")
    void testNullInputs_DoNotThrow() {
        assertDoesNotThrow(() -> {
            assertTrue(stringUtils.isEmpty(null));
            assertNull(stringUtils.reverse(null));
            assertFalse(stringUtils.isPalindrome(null));
            assertEquals(0, stringUtils.countWords(null));
        });
    }
}