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
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.junit.jupiter.params.provider.Arguments.of;
import org.junit.jupiter.params.provider.Arguments;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    interface Helper {
        String provide();
    }

    @Mock
    private Helper helper;

    @InjectMocks
    private StringUtils stringUtils;

    @BeforeEach
    void setUp() {
        if (stringUtils == null) {
            stringUtils = new StringUtils();
        }
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
    }

    // isEmpty tests
    @Test
    @DisplayName("isEmpty: null input should return true")
    void testIsEmpty_WithNullInput_ShouldReturnTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" should be treated as empty")
    @ValueSource(strings = {"", " ", "   ", "\t", "\n", "\r\n", " \t "})
    @DisplayName("isEmpty: blank strings should return true")
    void testIsEmpty_WithBlankInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest(name = "isEmpty: \"{0}\" should NOT be treated as empty")
    @ValueSource(strings = {"a", " a ", "test", "0", "😊", "abc\t"})
    @DisplayName("isEmpty: non-blank strings should return false")
    void testIsEmpty_WithNonBlankInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // reverse tests
    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_WithNullInput_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest(name = "reverse: \"{0}\" -> \"{1}\"")
    @MethodSource("reverseCases")
    @DisplayName("reverse: various inputs should be reversed correctly")
    void testReverse_WithVariousInputs_ShouldReturnReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    static Stream<Arguments> reverseCases() {
        return Stream.of(
                of("", ""),
                of("a", "a"),
                of("ab", "ba"),
                of("abc", "cba"),
                of("mañana", "anañam"),
                of("😊👍", "👍😊"),
                of(" ab ", " ba ")
        );
    }

    // isPalindrome tests
    @Test
    @DisplayName("isPalindrome: null input should return false")
    void testIsPalindrome_WithNullInput_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest(name = "isPalindrome: \"{0}\" should be true")
    @ValueSource(strings = {"", " ", "a", "aa", "aba", "Aba", "A man a plan a canal Panama", "nurses run"})
    @DisplayName("isPalindrome: known true cases")
    void testIsPalindrome_WithTrueCases_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest(name = "isPalindrome: \"{0}\" should be false")
    @ValueSource(strings = {"ab", "abc", "hello", "No 'x' in Nixon"})
    @DisplayName("isPalindrome: known false cases")
    void testIsPalindrome_WithFalseCases_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    // countWords tests
    @Test
    @DisplayName("countWords: null input should return 0")
    void testCountWords_WithNullInput_ShouldReturnZero() {
        assertEquals(0, stringUtils.countWords(null));
    }

    @ParameterizedTest(name = "countWords: \"{0}\" should return 0")
    @ValueSource(strings = {"", " ", " \t\n "})
    @DisplayName("countWords: blank strings should return 0")
    void testCountWords_WithBlankStrings_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest(name = "countWords: \"{0}\" -> {1}")
    @MethodSource("countWordsCases")
    @DisplayName("countWords: various sentences should return correct counts")
    void testCountWords_WithTypicalSentences_ShouldReturnCorrectCount(String input, int expectedCount) {
        assertEquals(expectedCount, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsCases() {
        return Stream.of(
                arguments("hello", 1),
                arguments("hello world", 2),
                arguments("hello   world", 2),
                arguments("  leading and trailing  ", 3),
                arguments("line1\nline2\tline3", 3),
                arguments("hello, world!", 2),
                arguments("naïve façade", 2),
                arguments("foo_bar baz42", 2)
        );
    }

    // Mockito usage to supply input
    @Test
    @DisplayName("reverse: should use mocked helper to provide input and reverse it")
    void testReverse_WithMockedHelperInput_ShouldReturnReversed() {
        when(helper.provide()).thenReturn("stressed");

        String result = stringUtils.reverse(helper.provide());

        assertEquals("desserts", result);
        verify(helper).provide();
    }

    // Exception handling using a spy to simulate an error path
    @Test
    @DisplayName("isEmpty: spy configured to throw should propagate exception")
    void testIsEmpty_WithSpyThrow_ShouldPropagateException() {
        StringUtils spyUtils = spy(new StringUtils());
        doThrow(new IllegalArgumentException("boom")).when(spyUtils).isEmpty("THROW");

        assertThrows(IllegalArgumentException.class, () -> spyUtils.isEmpty("THROW"));
        verify(spyUtils).isEmpty("THROW");
    }
}