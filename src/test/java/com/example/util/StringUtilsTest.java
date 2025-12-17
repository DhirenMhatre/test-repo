package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @Mock
    private Object unusedDependency;

    @InjectMocks
    private StringUtils stringUtils;

    @BeforeEach
    void setUp() {
        assertNotNull(stringUtils, "StringUtils should be initialized");
    }

    @AfterEach
    void tearDown() {
        // No resources to release for this simple utility class
    }

    // Providers

    static Stream<String> nullOrBlankStringsProvider() {
        return Stream.of(null, "", " ", "   ", "\t", "\n", " \t\n ");
    }

    static Stream<String> nonBlankStringsProvider() {
        return Stream.of("a", "abc", "  abc  ", "0", "false");
    }

    static Stream<Arguments> reverseCasesProvider() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("ab", "ba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of("Hello, World!", "!dlroW ,olleH"),
                Arguments.of("  a b  ", "  b a  ")
        );
    }

    static Stream<Arguments> palindromeCasesProvider() {
        return Stream.of(
                Arguments.of(null, false),
                Arguments.of("", true),
                Arguments.of(" ", true),
                Arguments.of("a", true),
                Arguments.of("ab", false),
                Arguments.of("racecar", true),
                Arguments.of("A man a plan a canal Panama", true),
                Arguments.of("No 'x' in Nixon", false) // punctuation not ignored by implementation
        );
    }

    static Stream<Arguments> countWordsCasesProvider() {
        return Stream.of(
                Arguments.of(null, 0),
                Arguments.of("", 0),
                Arguments.of("   ", 0),
                Arguments.of("Hello", 1),
                Arguments.of("Hello world", 2),
                Arguments.of("  multiple   spaces  here ", 3),
                Arguments.of("line1\nline2\tline3", 3),
                Arguments.of("hello-world", 1),
                Arguments.of(" tabs\tand  spaces  ", 3)
        );
    }

    // isEmpty tests

    @ParameterizedTest
    @MethodSource("nullOrBlankStringsProvider")
    @DisplayName("isEmpty: null or blank strings should return true")
    void testIsEmpty_NullOrBlankStrings_ReturnsTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @MethodSource("nonBlankStringsProvider")
    @DisplayName("isEmpty: non-blank strings should return false")
    void testIsEmpty_NonBlankStrings_ReturnsFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // reverse tests

    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_NullInput_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest
    @MethodSource("reverseCasesProvider")
    @DisplayName("reverse: various inputs should be reversed correctly")
    void testReverse_VariousInputs_ReturnsReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    // isPalindrome tests

    @ParameterizedTest
    @MethodSource("palindromeCasesProvider")
    @DisplayName("isPalindrome: various inputs should be evaluated correctly")
    void testIsPalindrome_VariousInputs_EvaluatedCorrectly(String input, boolean expected) {
        assertEquals(expected, stringUtils.isPalindrome(input));
    }

    // countWords tests

    @ParameterizedTest
    @MethodSource("countWordsCasesProvider")
    @DisplayName("countWords: various inputs should return correct word counts")
    void testCountWords_VariousInputs_ReturnsCorrectCount(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: should propagate exception when isEmpty throws")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        StringUtils spyUtils = spy(stringUtils);
        doThrow(new IllegalStateException("boom")).when(spyUtils).isEmpty(any());

        assertThrows(IllegalStateException.class, () -> spyUtils.countWords("test"));
        verify(spyUtils).isEmpty("test");
    }
}