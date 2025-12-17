package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils spyStringUtils;

    @BeforeEach
    void setUp() {
        assertNotNull(stringUtils, "StringUtils should be initialized");
        assertNotNull(spyStringUtils, "Spy StringUtils should be initialized");
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        spyStringUtils = null;
    }

    // isEmpty tests

    @Test
    @DisplayName("isEmpty: null input should return true")
    void testIsEmpty_WithNull_ShouldReturnTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" should be considered empty")
    @ValueSource(strings = {"", " ", "   ", "\t", "\n", " \n\t  "})
    @DisplayName("isEmpty: blank inputs should return true")
    void testIsEmpty_WithBlankInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" should NOT be considered empty")
    @ValueSource(strings = {"a", "abc", "  a  ", "0", "false"})
    @DisplayName("isEmpty: non-blank inputs should return false")
    void testIsEmpty_WithNonBlankInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_WithNull_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest(name = "reverse: \"{0}\" -> \"{1}\"")
    @MethodSource("reverseProvider")
    @DisplayName("reverse: should reverse strings correctly")
    void testReverse_VariousInputs_ShouldReverseCorrectly(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    static Stream<Arguments> reverseProvider() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("ab", "ba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of("hello", "olleh"),
                Arguments.of("  ab", "ba  "),
                Arguments.of("😊", "😊"),
                Arguments.of("😊a", "a😊")
        );
    }

    @Test
    @DisplayName("reverse: should not modify original input string")
    void testReverse_ShouldNotModifyOriginalInput() {
        String input = "abc";
        String original = input;
        String reversed = stringUtils.reverse(input);
        assertEquals("cba", reversed);
        assertEquals("abc", original);
    }

    // isPalindrome tests

    @Test
    @DisplayName("isPalindrome: null input should return false")
    void testIsPalindrome_WithNull_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest(name = "isPalindrome: \"{0}\" should be true")
    @ValueSource(strings = {
            "",
            " ",
            "a",
            "racecar",
            "A man a plan a canal Panama",
            "Never odd or even",
            "nurses run",
            "Was It A Rat I Saw"
    })
    @DisplayName("isPalindrome: valid palindromes should return true (ignoring spaces and case)")
    void testIsPalindrome_WithValidPalindromes_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest(name = "isPalindrome: \"{0}\" should be false")
    @ValueSource(strings = {
            "hello",
            "Java",
            "ab",
            "abc",
            "No lemon, no melon", // punctuation breaks this for current implementation
            "palindrome "
    })
    @DisplayName("isPalindrome: non-palindromes should return false")
    void testIsPalindrome_WithNonPalindromes_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    // countWords tests

    @Test
    @DisplayName("countWords: null input should return 0")
    void testCountWords_WithNull_ShouldReturnZero() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @ParameterizedTest(name = "countWords: \"{0}\" should return 0")
    @ValueSource(strings = {"", " ", "   ", "\t", "\n", "  \n\t  "})
    @DisplayName("countWords: blank inputs should return 0")
    void testCountWords_WithBlankInputs_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest(name = "countWords: \"{0}\" should return {1}")
    @MethodSource("countWordsProvider")
    @DisplayName("countWords: should count words separated by whitespace")
    void testCountWords_WithVariousInputs_ShouldReturnExpectedCount(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsProvider() {
        return Stream.of(
                Arguments.of("one", 1),
                Arguments.of("two words", 2),
                Arguments.of(" multiple   spaces ", 2),
                Arguments.of("line\nbreaks\ttabs", 3),
                Arguments.of(" leading space", 2),
                Arguments.of("trailing space ", 2),
                Arguments.of(" around ", 1),
                Arguments.of("emoji 😊 test", 3)
        );
    }

    @Test
    @DisplayName("countWords: should call isEmpty internally before processing")
    void testCountWords_ShouldCallIsEmptyInternally() {
        int count = spyStringUtils.countWords("hello world");
        assertEquals(2, count);
        verify(spyStringUtils, times(1)).isEmpty("hello world");
    }

    @Test
    @DisplayName("countWords: when isEmpty throws, exception should propagate")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        doThrow(new RuntimeException("boom")).when(spyStringUtils).isEmpty(anyString());
        assertThrows(RuntimeException.class, () -> spyStringUtils.countWords("abc"));
    }
}