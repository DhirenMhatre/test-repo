package main.java.com.example.util;

import main.java.com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EmptySource;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @Mock
    private Runnable mockDependency;

    @InjectMocks
    private StringUtils stringUtils;

    @BeforeEach
    void setUp() {
        // No initialization needed beyond @InjectMocks for this simple utility
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
    }

    @ParameterizedTest
    @NullSource
    @EmptySource
    @ValueSource(strings = {" ", "   ", "\n", "\t", " \n\t "})
    @DisplayName("isEmpty - Null or blank strings should be considered empty")
    void testIsEmpty_NullOrBlank_True(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " a ", "0", "false", "hello"})
    @DisplayName("isEmpty - Non-blank strings should not be considered empty")
    void testIsEmpty_NonBlank_False(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse - Null input should return null")
    void testReverse_NullInput_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse - Regular string should be reversed")
    void testReverse_RegularString_ReturnsReversed() {
        assertEquals("fedcba", stringUtils.reverse("abcdef"));
    }

    @Test
    @DisplayName("reverse - Unicode emoji (surrogate pairs) should be preserved correctly")
    void testReverse_UnicodeEmoji_PreservesSurrogatePairs() {
        String input = "A😀B";
        String expected = "B😀A";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("isPalindrome - Null input should return false")
    void testIsPalindrome_NullInput_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome - Whitespace-only string should be considered palindrome")
    void testIsPalindrome_WhitespaceOnly_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("   \t \n  "));
    }

    @Test
    @DisplayName("isPalindrome - Palindrome ignoring spaces and case should return true")
    void testIsPalindrome_PalindromeWithSpacesAndCase_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("A man a plan a canal Panama"));
    }

    @Test
    @DisplayName("isPalindrome - Non-palindrome should return false")
    void testIsPalindrome_NonPalindrome_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    @ParameterizedTest
    @NullSource
    @EmptySource
    @ValueSource(strings = {" ", "   ", "\n", "\t", " \n\t "})
    @DisplayName("countWords - Null or blank strings should return 0")
    void testCountWords_NullOrBlank_ReturnsZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest
    @MethodSource("countWordsProvider")
    @DisplayName("countWords - Various whitespace and punctuation cases should return expected counts")
    void testCountWords_VariousInputs_ReturnsExpectedCount(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<org.junit.jupiter.params.provider.Arguments> countWordsProvider() {
        return Stream.of(
                org.junit.jupiter.params.provider.Arguments.of("hello world", 2),
                org.junit.jupiter.params.provider.Arguments.of("  hello   world  ", 2),
                org.junit.jupiter.params.provider.Arguments.of("one two three", 3),
                org.junit.jupiter.params.provider.Arguments.of("line1\nline2\tline3", 3),
                org.junit.jupiter.params.provider.Arguments.of("hello, world!", 2),
                org.junit.jupiter.params.provider.Arguments.of("single", 1)
        );
    }

    @Test
    @DisplayName("reverse - Mockito stubbed method should throw IllegalArgumentException (assertThrows)")
    void testReverse_WithMockitoStub_ShouldThrowException() {
        StringUtils spyUtils = spy(stringUtils);
        doThrow(new IllegalArgumentException("boom")).when(spyUtils).reverse(any());

        assertThrows(IllegalArgumentException.class, () -> spyUtils.reverse("input"));
    }

    @Test
    @DisplayName("reverse - Mockito spy should be invoked and return stubbed value")
    void testReverse_WithMockitoSpy_ShouldReturnStubbedValue() {
        StringUtils spyUtils = spy(stringUtils);
        doReturn("zyx").when(spyUtils).reverse("xyz");

        String result = spyUtils.reverse("xyz");

        assertEquals("zyx", result);
        verify(spyUtils, times(1)).reverse("xyz");
    }
}