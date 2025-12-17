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
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    private StringUtils stringUtils;

    @Mock
    private StringUtils mockStringUtils;

    @BeforeEach
    void setUp() {
        stringUtils = new StringUtils();
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        reset(mockStringUtils);
    }

    // --------------------
    // isEmpty tests
    // --------------------

    @Test
    @DisplayName("isEmpty: null input -> true")
    void testIsEmpty_NullInput_ReturnsTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" -> true")
    @ValueSource(strings = {"", " ", "   ", "\t", "\n", " \t \n "})
    @DisplayName("isEmpty: blank or whitespace-only inputs -> true")
    void testIsEmpty_WhitespaceOnly_ReturnsTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" -> false")
    @ValueSource(strings = {"a", " a ", "abc", "0", "test"})
    @DisplayName("isEmpty: non-empty strings -> false")
    void testIsEmpty_NonEmptyStrings_ReturnsFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // --------------------
    // reverse tests
    // --------------------

    @Test
    @DisplayName("reverse: null input -> null")
    void testReverse_NullInput_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest(name = "reverse: \"{0}\" -> same string")
    @ValueSource(strings = {"", "a", " ", "Z"})
    @DisplayName("reverse: empty or single-character strings return unchanged")
    void testReverse_EmptyOrSingleCharacter_ReturnsSame(String input) {
        assertEquals(input, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: typical string -> reversed")
    void testReverse_TypicalString_ReturnsReversed() {
        assertEquals("cba", stringUtils.reverse("abc"));
        assertEquals("dlrow olleh", stringUtils.reverse("hello world"));
        assertEquals("aA", stringUtils.reverse("Aa"));
    }

    // --------------------
    // isPalindrome tests
    // --------------------

    @Test
    @DisplayName("isPalindrome: null input -> false")
    void testIsPalindrome_NullInput_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest(name = "isPalindrome true cases: \"{0}\"")
    @ValueSource(strings = {
            "racecar",
            "RaceCar",
            "A man a plan a canal Panama",
            "nurses run",
            " ",
            "   "
    })
    @DisplayName("isPalindrome: palindromic strings (ignoring spaces, case) -> true")
    void testIsPalindrome_PalindromicStrings_ReturnsTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest(name = "isPalindrome false cases: \"{0}\"")
    @ValueSource(strings = {
            "hello",
            "Java",
            "openai",
            "not a palindrome",
            "palin drome"
    })
    @DisplayName("isPalindrome: non-palindromic strings -> false")
    void testIsPalindrome_NonPalindromicStrings_ReturnsFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    // --------------------
    // countWords tests
    // --------------------

    static Stream<Arguments> countWordsProvider() {
        return Stream.of(
                Arguments.of(null, 0),
                Arguments.of("", 0),
                Arguments.of("   ", 0),
                Arguments.of("hello", 1),
                Arguments.of("hello world", 2),
                Arguments.of("  hello   world  ", 2),
                Arguments.of("hello\tworld\nfoo", 3),
                Arguments.of("hello-world", 1),
                Arguments.of("hello, world!", 2),
                Arguments.of("  multiple   spaces and\ttabs\n", 4),
                Arguments.of(" leading and trailing ", 3),
                Arguments.of("single", 1)
        );
    }

    @ParameterizedTest(name = "countWords: \"{0}\" -> {1}")
    @MethodSource("countWordsProvider")
    @DisplayName("countWords: handles null, empty, whitespace, and typical sentences")
    void testCountWords_VariousInputs_ReturnsExpectedCount(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    // --------------------
    // Mockito usage and exception tests
    // --------------------

    @Test
    @DisplayName("Mocked StringUtils: reverse throws IllegalArgumentException")
    void testReverse_WithMock_ShouldThrowException() {
        when(mockStringUtils.reverse(any())).thenThrow(new IllegalArgumentException("Invalid input"));
        assertThrows(IllegalArgumentException.class, () -> mockStringUtils.reverse("boom"));
        verify(mockStringUtils, times(1)).reverse("boom");
    }

    @Test
    @DisplayName("Mocked StringUtils: isEmpty invocation is verified")
    void testIsEmpty_WithMock_ShouldVerifyInvocation() {
        when(mockStringUtils.isEmpty("abc")).thenReturn(false);

        boolean result = mockStringUtils.isEmpty("abc");

        assertFalse(result);
        verify(mockStringUtils, times(1)).isEmpty("abc");
        verifyNoMoreInteractions(mockStringUtils);
    }
}